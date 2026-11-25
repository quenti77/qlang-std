import "app.q" as web
import "cache.q" as cc
import "limit.q" as lim
import "testing.q" as testing
import "test_blog.q" as blog
import "test_blog_controllers.q" as controllers

fun build(limit: int) -> web.App
    let app = web.App.new(Reflect.callables(blog))
    app.controllers(Reflect.callables(controllers))
    app.use(lim.rate_limit(cc.Cache.memory(), limit, 60, lim.by_header("x-client")))
    app
end

fun test_requests_over_the_limit_get_a_429_with_retry_after()
    let client = testing.Client.new(build(2))
    client.header("X-Client", "a")
    assert_eq(client.get("/posts").expect_status(200).header("x-ratelimit-remaining"), "1")
    client.get("/posts").expect_status(200)
    let refused = client.get("/posts").expect_status(429)
    assert_eq(refused.header("x-ratelimit-remaining"), "0")
    assert_eq(refused.header("retry-after") != none, true)
end

fun test_each_key_has_its_own_budget_and_the_window_resets()
    let app = build(1)
    let a = testing.Client.new(app)
    a.header("X-Client", "a")
    let b = testing.Client.new(app)
    b.header("X-Client", "b")
    a.get("/posts").expect_status(200)
    b.get("/posts").expect_status(200)
    a.get("/posts").expect_status(429)
    time.sleep(61000)
    a.get("/posts").expect_status(200)
end

fun test_a_limit_can_target_one_method_and_one_path()
    let app = web.App.new(Reflect.callables(blog))
    app.controllers(Reflect.callables(controllers))
    app.use(lim.rate_limit_on(["POST"], ["/posts"], cc.Cache.memory(), 1, 60, lim.by_client_ip()))
    let client = testing.Client.new(app)
    client.header("X-Forwarded-For", "10.0.0.1, 10.0.0.9")
    let form = { "title": "Third one" }
    client.post_form("/posts", form).expect_status(201)
    client.get("/posts").expect_status(200)
    client.get("/posts").expect_status(200)
    client.post_form("/posts", form).expect_status(429)
    let other = testing.Client.new(app)
    other.header("X-Forwarded-For", "10.0.0.2")
    other.post_form("/posts", form).expect_status(201)
end

fun test_the_key_is_the_forwarded_address_or_the_one_of_the_connection()
    let direct = Request { method: "GET", url: "/", path: "/", remote_addr: "192.168.1.5" }
    assert_eq(lim.by_client_ip()(direct), "192.168.1.5")
    assert_eq(lim.by_remote_addr()(direct), "192.168.1.5")
    assert_eq(lim.by_remote_addr()(Request { method: "GET", url: "/", path: "/" }), "unknown")
    let proxied = Request { method: "GET", url: "/", path: "/", remote_addr: "10.0.0.1", headers: { "x-forwarded-for": "203.0.113.7, 10.0.0.1" } }
    assert_eq(lim.by_client_ip()(proxied), "203.0.113.7")
end

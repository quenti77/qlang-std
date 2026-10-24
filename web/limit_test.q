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

import "app.q" as web
import "health.q" as hl
import "testing.q" as testing

fun app_with(health: hl.Health) -> web.App
    let app = web.App.new([])
    health.mount(app, "/health")
    app
end

fun test_liveness_always_answers_200()
    let health = hl.Health.new()
    health.check("database", fun() -> string? "down" end)
    let client = testing.Client.new(app_with(health))
    client.get("/health/live").expect_status(200)
end

fun test_readiness_is_200_when_every_check_passes()
    let health = hl.Health.new()
    health.check("database", fun() -> string? none end)
    let client = testing.Client.new(app_with(health))
    let res = client.get("/health/ready").expect_status(200)
    assert(res.body.contains("\"status\":\"ok\""))
end

fun test_readiness_is_503_and_names_the_failing_check_without_its_reason()
    let health = hl.Health.new()
    health.check("database", fun() -> string? none end)
    health.check("redis", fun() -> string? "connection refused at 10.0.0.5" end)
    let client = testing.Client.new(app_with(health))
    let res = client.get("/health/ready").expect_status(503)
    assert(res.body.contains("redis"))
    assert(res.body.contains("failing"))
    assert(not res.body.contains("10.0.0.5"))
end

fun test_ready_gives_the_status_and_the_body()
    let health = hl.Health.new()
    assert_eq(health.ready().0, 200)
    health.check("x", fun() -> string? "no" end)
    assert_eq(health.ready().0, 503)
end

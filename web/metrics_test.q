import "metrics.q" as mt
import "health.q" as hl
import "app.q" as web
import "cache.q" as cc
import "testing.q" as testing
import "../queue.q" as jobs

fun build(cache: cc.Cache) -> (web.App, mt.Metrics)
  let app = web.App.new([])
  app.get("/posts/:id", fun(req: Request) -> Response Response.text("post") end)
  app.get("/boom", fun(req: Request) -> Response Response.text("no").with_status(500) end)
  let metrics = mt.Metrics.new(cache, app)
  app.use(metrics.middleware())
  metrics.mount(app, "/metrics", fun(req: Request) -> Response? none end)
  (app, metrics)
end

fun test_requests_are_counted_by_route_pattern_not_by_path()
  let built = build(cc.Cache.memory())
  let client = testing.Client.new(built.0)
  client.get("/posts/1")
  client.get("/posts/2")
  client.get("/boom")
  client.get("/nothing/here")
  let page = client.get("/metrics").expect_status(200).body
  assert(page.contains("http_requests_total\{method=\"GET\",route=\"/posts/:id\",status=\"2xx\"\} 2"))
  assert(page.contains("http_requests_total\{method=\"GET\",route=\"/boom\",status=\"5xx\"\} 1"))
  assert(page.contains("http_requests_total\{method=\"GET\",route=\"unmatched\",status=\"4xx\"\} 1"))
  assert(not page.contains("/posts/1"))
  assert(page.contains("http_request_duration_ms_count\{route=\"/posts/:id\"\} 2"))
  assert(page.contains("http_request_duration_ms_bucket\{route=\"/posts/:id\",le=\"+Inf\"\} 2"))
end

fun test_two_apps_sharing_a_cache_add_up_like_two_workers()
  let shared = cc.Cache.memory()
  let a = testing.Client.new(build(shared).0)
  let b = testing.Client.new(build(shared).0)
  a.get("/posts/1")
  b.get("/posts/2")
  b.get("/posts/3")
  assert(a.get("/metrics").body.contains("route=\"/posts/:id\",status=\"2xx\"\} 3"))
end

fun test_the_guard_protects_the_page_and_the_queue_is_reported()
  let app = web.App.new([])
  let metrics = mt.Metrics.new(cc.Cache.memory(), app)
  let queue = jobs.Queue.new(Db.connect("sqlite://:memory:").unwrap(), "sqlite")
  queue.install().unwrap()
  metrics.with_queue(queue)
  metrics.mount(app, "/metrics", fun(req: Request) -> Response? Response.text("no").with_status(401) end)
  testing.Client.new(app).get("/metrics").expect_status(401)
  assert(metrics.render().contains("queue_jobs_pending 0"))
end

fun test_health_live_is_always_ok_and_ready_reports_failures_without_their_text()
  let app = web.App.new([])
  let health = hl.Health.new()
  health.check("database", hl.db_check(Db.connect("sqlite://:memory:").unwrap()))
  health.check("cache", fun() -> string? "connection to 10.0.0.5 refused" end)
  health.mount(app, "/health")
  let client = testing.Client.new(app)
  client.get("/health/live").expect_status(200)
  let ready = client.get("/health/ready").expect_status(503)
  assert(ready.body.contains("\"cache\""))
  assert(not ready.body.contains("10.0.0.5"))
  let fine = hl.Health.new()
  fine.check("database", hl.db_check(Db.connect("sqlite://:memory:").unwrap()))
  assert_eq(fine.ready().0, 200)
end

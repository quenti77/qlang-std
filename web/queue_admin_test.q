import "queue_admin.q" as admin
import "app.q" as web
import "testing.q" as testing
import "../queue.q" as jobs

struct Doomed
  public why: string
end

fun build(open: bool) -> (web.App, jobs.Queue)
  let queue = jobs.Queue.new(Db.connect("sqlite://:memory:").unwrap(), "sqlite")
  queue.install().unwrap()
  queue.max_attempts = 1
  queue.handle<Doomed>(fun(d: Doomed) -> string? "<b>boom</b>" end)
  let app = web.App.new([])
  let guard = fun(req: Request) -> Response?
    if open or req.headers["x-admin"] == "yes" then none else Response.text("no").with_status(403) end
  end
  admin.mount(app, queue, "/admin/queue", guard)
  (app, queue)
end

fun test_the_dashboard_shows_the_pending_and_failed_jobs_and_escapes_them()
  let built = build(true)
  let queue = built.1
  queue.push(Doomed { why: "<script>" }).unwrap()
  queue.push(Doomed { why: "b" }).unwrap()
  queue.work_one().unwrap()
  let client = testing.Client.new(built.0)
  let stats = client.get("/admin/queue/stats").expect_status(200)
  let json = Json.parse(stats.body).unwrap()
  assert_eq((json.get("pending") ?? Json.null()).as_number() as int, 1)
  assert_eq((json.get("failed") ?? Json.null()).as_array().len(), 1)
  let html = client.get("/admin/queue").expect_status(200)
  assert(html.body.contains("&lt;b&gt;boom&lt;/b&gt;"))
  assert(not html.body.contains("<b>boom</b>"))
end

fun test_retry_and_forget_act_on_failed_jobs()
  let built = build(true)
  let queue = built.1
  queue.push(Doomed { why: "a" }).unwrap()
  queue.work_one().unwrap()
  let id = queue.failed().unwrap()[0].id
  let client = testing.Client.new(built.0)
  client.post("/admin/queue/retry/{id}", "").expect_status(200)
  assert_eq(queue.failed().unwrap().len(), 0)
  assert_eq(queue.pending().unwrap(), 1)
  client.post("/admin/queue/retry/999", "").expect_status(404)
  queue.work_one().unwrap()
  let again = queue.failed().unwrap()[0].id
  client.post("/admin/queue/forget/{again}", "").expect_status(200)
  assert_eq(queue.failed().unwrap().len(), 0)
end

fun test_the_guard_protects_every_route()
  let built = build(false)
  let client = testing.Client.new(built.0)
  client.get("/admin/queue").expect_status(403)
  client.get("/admin/queue/stats").expect_status(403)
  client.post("/admin/queue/retry/1", "").expect_status(403)
  client.header("x-admin", "yes")
  client.get("/admin/queue/stats").expect_status(200)
end

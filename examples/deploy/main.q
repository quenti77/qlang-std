-- The web process of the deployment example:  qlang serve examples/deploy/main.q
-- Configuration comes from the environment (12-factor): REDIS_URL, DATABASE_URL, METRICS_TOKEN.
import "../../web/app.q" as web
import "../../web/cache.q" as cc
import "../../web/health.q" as hl
import "../../web/metrics.q" as mt
import "../../web/middleware.q" as mw
import "../../queue.q" as jobs

struct Hello
  public name: string
end

let redis_url = env.get("REDIS_URL")
let database_url = env.get("DATABASE_URL") ?? "sqlite://app.db"
let db = Db.connect(database_url).unwrap()
let cache = if redis_url == none then cc.Cache.memory() else cc.Cache.redis(Redis.connect(redis_url).unwrap(), "app") end
let queue = jobs.Queue.new(db, "sqlite")
queue.install().unwrap()

let app = web.App.new([])
app.get("/", fun(req: Request) -> Response Response.text("hello from qlang") end)
app.post("/hello/:name", fun(req: Request) -> Response
  queue.push(Hello { name: req.params["name"] ?? "?" }).unwrap()
  Response.text("queued").with_status(202)
end)

-- what an operator needs
let health = hl.Health.new()
health.check("database", hl.db_check(db))
health.mount(app, "/health")
let metrics = mt.Metrics.new(cache, app).with_queue(queue)
let token = env.get("METRICS_TOKEN") ?? ""
metrics.mount(app, "/metrics", fun(req: Request) -> Response?
  if token != "" and Crypto.equal(req.headers["authorization"] ?? "", "Bearer {token}") then none else Response.text("unauthorized").with_status(401) end
end)
app.use(metrics.middleware())
app.use(mw.logging())

fun handle(req: Request) -> Response
  app.handle(req)
end

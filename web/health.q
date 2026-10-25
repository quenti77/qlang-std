--" # Health checks

Two pages for the system that runs your application (a load balancer, Kubernetes, a monitoring service):

- **liveness** (`/health/live`): the process answers. Always `200`. If it does not, restart it.
- **readiness** (`/health/ready`): the things it needs work (the database, Redis, a disk). `200` when all
  checks pass, `503` otherwise, with one line per check. If it fails, stop sending requests, do not restart.

```
let health = Health.new()
health.check("database", db_check(db))
health.check("redis", redis_check(redis))
health.mount(app, "/health")
```

A check is a function that gives `none` when it went well, or a text that says why not. The page says which
check failed, never the text of the error (it may name a host or a table): that goes to the log.
--"
import "app.q" as web

--" The checks of the application. --"
struct Health
  public checks: array<(string, fun() -> string?)>
end

--" A check that runs `SELECT 1` on the database. --"
fun db_check(db: Db) -> fun() -> string?
  fun() -> string?
    let r = db.query("SELECT 1", [])
    if r.is_err() then r.unwrap_err().message else none end
  end
end

--" A check that sends `PING` to Redis. --"
fun redis_check(redis: Redis) -> fun() -> string?
  fun() -> string?
    let r = redis.command(["PING"])
    if r.is_err() then r.unwrap_err().message else none end
  end
end

impl Health
  public fun new() -> Health
    Health { checks: [] }
  end

  public fun check(self, name: string, run: fun() -> string?)
    self.checks.push((name, run))
  end

  --" Runs the checks. Gives the status code and the JSON body. --"
  public fun ready(self) -> (int, string)
    let ok = true
    let parts: map<string, Json> = {}
    for c in self.checks do
      let started = time.now()
      let why = c.1()
      let ms = time.now() - started
      if why != none then
        ok = false
        Log.error("health check {c.0} failed: {why}")
      end
      parts[c.0] = Json.object({"status": Json.string(if why == none then "ok" else "failing" end), "ms": Json.number(ms as float)})
    end
    (if ok then 200 else 503 end, Json.object({"status": Json.string(if ok then "ok" else "failing" end), "checks": Json.object(parts)}).to_text())
  end

  --" Adds `path/live` and `path/ready`. --"
  public fun mount(self, app: web.App, path: string)
    app.get("{path}/live", fun(req: Request) -> Response
      Response.json("\{\"status\":\"ok\"\}")
    end)
    app.get("{path}/ready", fun(req: Request) -> Response
      let r = self.ready()
      Response.json(r.1).with_status(r.0)
    end)
  end
end

export Health, db_check, redis_check

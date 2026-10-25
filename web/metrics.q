--" # Metrics

Counts the requests and the time they take, and serves them in the format that
[Prometheus](https://prometheus.io) reads (`GET /metrics`):

```
let metrics = Metrics.new(Cache.redis(redis, "metrics"), app)
app.use(metrics.middleware())
metrics.mount(app, "/metrics", guard)       -- `guard` keeps the page for your monitoring
```

```
http_requests_total{method="GET",route="/posts/:id",status="2xx"} 1042
http_request_duration_ms_bucket{route="/posts/:id",le="50"} 990
http_request_duration_ms_count{route="/posts/:id"} 1042
```

The counters live in the `Cache` you give. With `qlang serve --workers 4` each worker is a program of its own, so
**use a shared cache (`Cache.redis`)**: with the default memory cache each scrape would show whichever worker
answered. Labels are the **route pattern** (`/posts/:id`, never `/posts/42`), so the number of series stays small;
a request that no route took is `unmatched`. Routes are read when `Metrics.new` is called: create it after the
routes exist. There is no `_sum` series (a cache counter only adds 1): the buckets give the quantiles
(`histogram_quantile`).

`with_queue(queue)` adds `queue_jobs_pending` and `queue_jobs_failed` to the page.
--"
import "app.q" as web
import "cache.q" as cc
import "../queue.q" as jobs

const LIFETIME = 315360000

--" Request counters kept in a cache. --"
struct Metrics
  public cache: cc.Cache
  public routes: array<string>
  public methods: array<string>
  --" Upper limits of the duration buckets, in milliseconds. --"
  public buckets: array<int> = [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
  public queue: jobs.Queue?
end

fun class_of(status: int) -> string
  "{status div 100}xx"
end

impl Metrics
  --" Counters for the routes of `app` (read now). --"
  public fun new(cache: cc.Cache, app: web.App) -> Metrics
    let routes: array<string> = []
    let methods: array<string> = []
    for r in app.route_list() do
      if not routes.contains(r.pattern) then
        routes.push(r.pattern)
      end
      if not methods.contains(r.method) then
        methods.push(r.method)
      end
    end
    Metrics { cache: cache, routes: routes, methods: methods, buckets: [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000], queue: none }
  end

  --" Adds the size of the job queue to the page. --"
  public fun with_queue(self, queue: jobs.Queue) -> Metrics
    self.queue = queue
    self
  end

  fun label(self, req: Request) -> string
    let found = req.attrs["route"]
    if found == none then
      return "unmatched"
    end
    found.as<string>() ?? "unmatched"
  end

  --" Counts every request and its duration. Put it first (`app.use`) to also count what other middleware refuses. --"
  public fun middleware(self) -> web.Middleware
    fun(req: Request, next: web.Handler) -> Response
      let started = time.now()
      let res = next(req)
      let ms = time.now() - started
      let route = self.label(req)
      self.cache.increment("req:{req.method}:{route}:{class_of(res.status)}", LIFETIME)
      self.cache.increment("count:{route}", LIFETIME)
      for b in self.buckets do
        if ms <= b then
          self.cache.increment("le:{route}:{b}", LIFETIME)
        end
      end
      res
    end
  end

  fun read(self, key: string) -> int
    int.parse(self.cache.get_text(key) ?? "0") ?? 0
  end

  --" The page in the Prometheus text format. --"
  public fun render(self) -> string
    let lines: array<string> = ["# TYPE http_requests_total counter"]
    let all = self.routes.concat(["unmatched"])
    for route in all do
      for method in self.methods.concat(["HEAD", "OPTIONS"]) do
        for status in ["2xx", "3xx", "4xx", "5xx", "1xx"] do
          let n = self.read("req:{method}:{route}:{status}")
          if n > 0 then
            lines.push("http_requests_total\{method=\"{method}\",route=\"{route}\",status=\"{status}\"\} {n}")
          end
        end
      end
    end
    lines.push("# TYPE http_request_duration_ms histogram")
    for route in all do
      let count = self.read("count:{route}")
      if count == 0 then
        continue
      end
      for b in self.buckets do
        lines.push("http_request_duration_ms_bucket\{route=\"{route}\",le=\"{b}\"\} {self.read("le:{route}:{b}")}")
      end
      lines.push("http_request_duration_ms_bucket\{route=\"{route}\",le=\"+Inf\"\} {count}")
      lines.push("http_request_duration_ms_count\{route=\"{route}\"\} {count}")
    end
    let q = self.queue
    if q != none then
      let pending = q.pending()
      let failed = q.failed()
      lines.push("# TYPE queue_jobs_pending gauge")
      lines.push("queue_jobs_pending {if pending.is_ok() then pending.unwrap() else -1 end}")
      lines.push("# TYPE queue_jobs_failed gauge")
      lines.push("queue_jobs_failed {if failed.is_ok() then failed.unwrap().len() else -1 end}")
    end
    lines.join("\n") + "\n"
  end

  --" Adds `GET path` that serves the page, behind `guard` (give one: metrics tell attackers how your site is used). --"
  public fun mount(self, app: web.App, path: string, guard: web.GuardFn)
    app.get(path, fun(req: Request) -> Response
      let stopped = guard(req)
      if stopped != none then
        return stopped
      end
      let res = Response.text(self.render())
      res.headers["Content-Type"] = "text/plain; version=0.0.4; charset=utf-8"
      res
    end)
  end
end

export Metrics

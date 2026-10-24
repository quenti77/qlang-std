--" # Queue dashboard

Routes to look at the job queue and act on failed jobs, behind a guard of yours:

```
queue_admin.mount(app, queue, "/admin/queue", auth_guard)
```

| Route | Gives |
| --- | --- |
| `GET /admin/queue` | an HTML page: how many jobs wait and the failed jobs, each with its error |
| `GET /admin/queue/stats` | `{"pending": 3, "failed": [{"id", "queue", "kind", "attempts", "error"}]}` |
| `POST /admin/queue/retry/:id` | puts a failed job back in the queue |
| `POST /admin/queue/forget/:id` | deletes a failed job |

The page only reads; the two `POST` routes are for your own buttons or for `curl`. Put your CSRF
protection and your admin check in the guard, never leave this open. A job's fields are shown as they were
written (they may hold personal data: show the page to the people who may see it).
--"
import "app.q" as web
import "../queue.q" as jobs

fun escape(s: string) -> string
  s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")
end

fun failure(error: Error) -> Response
  Response.json(Json.object({"error": Json.string(error.message)}).to_text()).with_status(500)
end

fun page(pending: int, failed: array<jobs.FailedJob>, path: string) -> string
  let rows = failed.map(fun(f: jobs.FailedJob) -> string
    "<tr><td>{escape(f.id)}</td><td>{escape(f.queue)}</td><td>{escape(f.kind)}</td><td>{f.attempts}</td><td>{escape(f.error)}</td><td><code>{escape(f.payload)}</code></td></tr>"
  end)
  let body = if rows.is_empty() then "<p>No failed job.</p>" else "<table><thead><tr><th>id</th><th>queue</th><th>type</th><th>attempts</th><th>error</th><th>job</th></tr></thead><tbody>{rows.join("")}</tbody></table>" end
  "<!doctype html><html><head><meta charset=\"utf-8\"><title>Queue</title><style>body\{font-family:system-ui;margin:2rem\}table\{border-collapse:collapse\}td,th\{border:1px solid #ccc;padding:.3rem .6rem;text-align:left\}</style></head><body><h1>Queue</h1><p>{pending} job(s) waiting or running, {failed.len()} failed.</p>{body}<p><small>Retry: POST {escape(path)}/retry/&lt;id&gt;</small></p></body></html>"
end

--" Adds the dashboard routes under `path`; `guard` runs first on each of them (`none`: let through). --"
fun mount(app: web.App, queue: jobs.Queue, path: string, guard: web.GuardFn)
  let stats = fun(req: Request) -> Response
    let stopped = guard(req)
    if stopped != none then
      return stopped
    end
    let pending = queue.pending()
    let failed = queue.failed()
    if pending.is_err() then
      return failure(pending.unwrap_err())
    end
    if failed.is_err() then
      return failure(failed.unwrap_err())
    end
    let list = failed.unwrap().map(fun(f: jobs.FailedJob) -> Json
      Json.object({"id": Json.string(f.id), "queue": Json.string(f.queue), "kind": Json.string(f.kind), "attempts": Json.number(f.attempts as float), "error": Json.string(f.error)})
    end)
    Response.json(Json.object({"pending": Json.number(pending.unwrap() as float), "failed": Json.array(list)}).to_text())
  end
  app.get("{path}/stats", stats)
  app.get(path, fun(req: Request) -> Response
    let stopped = guard(req)
    if stopped != none then
      return stopped
    end
    let pending = queue.pending()
    let failed = queue.failed()
    if pending.is_err() then
      return failure(pending.unwrap_err())
    end
    if failed.is_err() then
      return failure(failed.unwrap_err())
    end
    Response.html(page(pending.unwrap(), failed.unwrap(), path))
  end)
  app.post("{path}/retry/:id", fun(req: Request) -> Response
    let stopped = guard(req)
    if stopped != none then
      return stopped
    end
    let again = queue.retry_failed(req.params["id"] ?? "")
    if again.is_err() then
      return failure(again.unwrap_err())
    end
    Response.json(Json.object({"retried": Json.boolean(again.unwrap())}).to_text()).with_status(if again.unwrap() then 200 else 404 end)
  end)
  app.post("{path}/forget/:id", fun(req: Request) -> Response
    let stopped = guard(req)
    if stopped != none then
      return stopped
    end
    let gone = queue.forget_failed(req.params["id"] ?? "")
    if gone.is_err() then
      return failure(gone.unwrap_err())
    end
    Response.json(Json.object({"forgotten": Json.boolean(gone.unwrap())}).to_text()).with_status(if gone.unwrap() then 200 else 404 end)
  end)
end

export mount

--" # Rate limiting

Refuses (`429 Too Many Requests`, with `Retry-After`) the clients that ask too often. Requests are
counted per key in windows of fixed length, in a `Cache`.

```
let cache = Cache.memory()
app.use(rate_limit(cache, 100, 60, by_header("x-forwarded-for")))   -- 100 requests a minute
app.use(rate_limit(cache, 5, 60, by_path_and_header("authorization")))
```

The counters live in the cache: a memory cache counts per worker (a limit of 100 with four
workers lets up to 400 through), a file cache counts for the machine. Behind a proxy, count by the
header the proxy sets (`x-forwarded-for`); do not trust that header when the client can reach the
server directly, since it can then write anything in it.
--"
import "app.q" as web
import "cache.q" as cc

--" Counts by the value of a request header (`"unknown"` when absent). --"
fun by_header(name: string) -> fun(Request) -> string
  fun(req: Request) -> string
    req.header(name) ?? "unknown"
  end
end

--" Counts by header and path, so that one client has a budget per route. --"
fun by_path_and_header(name: string) -> fun(Request) -> string
  fun(req: Request) -> string
    "{req.header(name) ?? "unknown"} {req.path}"
  end
end

--" At most `limit` requests per `seconds` for each key `key_of` gives. The answers carry
`X-RateLimit-Limit` and `X-RateLimit-Remaining`. --"
fun rate_limit(cache: cc.Cache, limit: int, seconds: int, key_of: fun(Request) -> string) -> web.Middleware
  let counters = cache.scoped("rate")
  fun(req: Request, next: web.Handler) -> Response
    let window = time.now() div (seconds * 1000)
    let key = "{key_of(req)}@{window}"
    let seen = counters.get<int>(key) ?? 0
    if seen >= limit then
      let left = seconds - (time.now() div 1000) mod seconds
      let res = web.Problem { status: 429, message: "Too Many Requests" }.to_response()
      res.headers["Retry-After"] = "{left}"
      res.headers["X-RateLimit-Limit"] = "{limit}"
      res.headers["X-RateLimit-Remaining"] = "0"
      return res
    end
    counters.put<int>(key, seen + 1, seconds * 2)
    let res = next(req)
    res.headers["X-RateLimit-Limit"] = "{limit}"
    res.headers["X-RateLimit-Remaining"] = "{limit - seen - 1}"
    res
  end
end

export rate_limit, by_header, by_path_and_header

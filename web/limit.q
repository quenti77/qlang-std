--" # Rate limiting

Refuses (`429 Too Many Requests`, with `Retry-After`) the clients that ask too often. Requests are
counted per key in windows of fixed length, in a `Cache`.

```
let cache = Cache.memory()
app.use(rate_limit(cache, 100, 60, by_header("x-forwarded-for")))   -- 100 requests a minute
app.use(rate_limit(cache, 5, 60, by_path_and_header("authorization")))
```

The counters live in the cache: a memory cache counts per worker (a limit of 100 with four
workers lets up to 400 through), a file cache counts for the machine, a Redis cache
(`Cache.redis(redis, "limit:")`) counts exactly for every machine (the count is one atomic step). Behind a proxy, count by the
header the proxy sets (`x-forwarded-for`); do not trust that header when the client can reach the
server directly, since it can then write anything in it.
--"
import "app.q" as web
import "cache.q" as cc
import "proxy.q" as proxy

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
        let window = time.now() // (seconds * 1000)
        let key = "{key_of(req)}@{window}"
        let seen = counters.increment(key, seconds * 2) - 1
        if seen >= limit then
            let left = seconds - (time.now() // 1000) mod seconds
            let res = web.Problem { status: 429, message: "Too Many Requests" }.to_response()
            res.headers["Retry-After"] = "{left}"
            res.headers["X-RateLimit-Limit"] = "{limit}"
            res.headers["X-RateLimit-Remaining"] = "0"
            return res
        end
        let res = next(req)
        res.headers["X-RateLimit-Limit"] = "{limit}"
        res.headers["X-RateLimit-Remaining"] = "{limit - seen - 1}"
        res
    end
end

--" Counts by the address of the client that is connected to the server (`"unknown"` if it is not
known). Behind a reverse proxy that is the proxy itself: use `by_client_ip` there. --"
fun by_remote_addr() -> fun(Request) -> string
    fun(req: Request) -> string
        if req.remote_addr.is_empty() then "unknown" else req.remote_addr end
    end
end

--" Counts by the first address of `X-Forwarded-For` when the proxy sent one, else by the address
of the connection. Only trust it behind a proxy that sets the header: a client that reaches the
server directly can write anything in it and so choose its own count. --"
fun by_client_ip() -> fun(Request) -> string
    let direct = by_remote_addr()
    fun(req: Request) -> string
        proxy.client_ip(req) ?? direct(req)
    end
end

--" Like `rate_limit`, for the requests of one of `methods` to one of `paths` only (exact paths: the
login of a site, for example `rate_limit_on(["POST"], ["/login", "/api/login"], cache, 5, 60, by_client_ip())`);
every other request goes through unlimited. --"
fun rate_limit_on(methods: array<string>, paths: array<string>, cache: cc.Cache, limit: int, seconds: int, key_of: fun(Request) -> string) -> web.Middleware
    let limited = rate_limit(cache, limit, seconds, key_of)
    fun(req: Request, next: web.Handler) -> Response
        if methods.contains(req.method.upper()) and paths.contains(req.path) then
            limited(req, next)
        else
            next(req)
        end
    end
end

export rate_limit, rate_limit_on, by_header, by_path_and_header, by_remote_addr, by_client_ip

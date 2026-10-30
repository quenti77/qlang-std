--" # Ready-made middleware

A middleware is a function `fun(req: Request, next: Handler) -> Response`: it can answer instead of
the route, change the request before `next(req)`, or change the response after it. Add them with
`app.use(...)`; the first one added is the outermost.

```
app.use(logging())
app.use(security_headers())
app.use(cors(["https://app.example"]))
app.use(bearer_token(fun(token: string) -> bool Crypto.equal(token, secret) end))
```

Needs a clock (`logging` measures the time of each request).
--"
import "app.q" as web

--" Writes one line in the log for each request: `GET /posts/2 -> 200 (3 ms)`, at the level `info`
(`warn` for a 4xx, `error` for a 5xx). --"
fun logging() -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    let started = time.now()
    let res = next(req)
    let ms = time.now() - started
    let line = "{req.method} {req.path} -> {res.status} ({ms} ms)"
    if res.status >= 500 then
      Log.error(line)
    else
      if res.status >= 400 then
        Log.warning(line)
      else
        Log.info(line)
      end
    end
    res
  end
end

--" Adds the usual protective headers: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
`Referrer-Policy: same-origin`. A header the route already set is kept. --"
fun security_headers() -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    let res = next(req)
    for pair in [("X-Content-Type-Options", "nosniff"), ("X-Frame-Options", "DENY"), ("Referrer-Policy", "same-origin")] do
      if res.headers[pair.0] == none then
        res.headers[pair.0] = pair.1
      end
    end
    res
  end
end

--" What `cors_with` allows. --"
struct CorsOptions
  --" The origins that may call (`"https://app.example"`), or `"*"` for any. --"
  public origins: array<string>
  public methods: array<string> = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
  --" The request headers allowed; empty means the ones the browser asks for. --"
  public headers: array<string> = []
  --" Response headers the page may read (`X-Request-Id`...). --"
  public expose: array<string> = []
  --" Lets the page send cookies and credentials; then the origin is repeated, never `*`. --"
  public credentials: bool = false
  --" Seconds a browser may keep the answer to a preflight request. --"
  public max_age: int = 600
end

--" Lets browsers of these origins (`["https://app.example"]`, or `["*"]`) call the API from a
page: answers the preflight `OPTIONS` request itself and adds `Access-Control-Allow-Origin` to
the other answers. --"
fun cors(origins: array<string>) -> web.Middleware
  cors_with(CorsOptions { origins: origins })
end

--" `cors` with every option: methods, headers, exposed headers, credentials, preflight cache. --"
fun cors_with(o: CorsOptions) -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    let origin = req.header("origin")
    if origin == none then
      return next(req)
    end
    let any = o.origins.contains("*")
    if not any and not o.origins.contains(origin) then
      return next(req)
    end
    let shown = if any and not o.credentials then "*" else origin end
    if req.method == "OPTIONS" and req.header("access-control-request-method") != none then
      let wanted = req.header("access-control-request-headers")
      let res = Response { status: 204, body: "" }
      res.headers["Access-Control-Allow-Origin"] = shown
      res.headers["Access-Control-Allow-Methods"] = o.methods.join(", ")
      if o.headers.len() > 0 then
        res.headers["Access-Control-Allow-Headers"] = o.headers.join(", ")
      else
        res.headers["Access-Control-Allow-Headers"] = if wanted == none then "Content-Type, Authorization" else wanted end
      end
      if o.credentials then
        res.headers["Access-Control-Allow-Credentials"] = "true"
      end
      res.headers["Access-Control-Max-Age"] = "{o.max_age}"
      res.headers["Vary"] = "Origin"
      return res
    end
    let res = next(req)
    res.headers["Access-Control-Allow-Origin"] = shown
    if o.credentials then
      res.headers["Access-Control-Allow-Credentials"] = "true"
    end
    if o.expose.len() > 0 then
      res.headers["Access-Control-Expose-Headers"] = o.expose.join(", ")
    end
    res.headers["Vary"] = "Origin"
    res
  end
end

--" Refuses (`401`) the requests that do not carry `Authorization: Bearer <token>` with a token
that `check` accepts. Compare secrets with `Crypto.equal` inside `check`. The token is put in
`req.attrs["token"]` for the handlers. --"
fun bearer_token(check: fun(string) -> bool) -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    let header = req.header("authorization")
    if header == none or not header.lower().starts_with("bearer ") then
      return unauthorized()
    end
    let token = header.substring(7, header.len()).trim()
    if token == "" or not check(token) then
      return unauthorized()
    end
    req.attrs["token"] = Any.of(token)
    next(req)
  end
end

fun unauthorized() -> Response
  let res = web.Problem { status: 401, message: "Unauthorized" }.to_response()
  res.headers["WWW-Authenticate"] = "Bearer"
  res
end

--" Gives each request an identifier: the `X-Request-Id` it came with, or a new one. It is put in
`req.attrs["request_id"]` and in the response's `X-Request-Id`. --"
fun request_id() -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    let given = req.header("x-request-id")
    let id = ""
    if given != none and given.len() <= 64 then
      id = given
    else
      let made = Crypto.token(9)
      id = if made.is_ok() then made.unwrap() else "unknown" end
    end
    req.attrs["request_id"] = Any.of(id)
    let res = next(req)
    res.headers["X-Request-Id"] = id
    res
  end
end

export logging, security_headers, cors, cors_with, CorsOptions, bearer_token, request_id

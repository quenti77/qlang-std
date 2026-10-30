--" # Behind a reverse proxy (TLS)

`qlang serve` speaks plain HTTP. HTTPS is done by a reverse proxy in front of it (Caddy, nginx,
Traefik, a load balancer of your host): it holds the certificate, renews it, and talks to qlang on
the same machine. Start qlang on the loopback address so that only the proxy can reach it:

```
qlang serve app.q --bind 127.0.0.1 --port 8080
```

The proxy must **replace** (not add to) the headers `X-Forwarded-For` and `X-Forwarded-Proto` with what
it saw itself; Caddy's `reverse_proxy` and nginx with `proxy_set_header X-Forwarded-For $remote_addr;`
`proxy_set_header X-Forwarded-Proto $scheme;` do. These helpers trust them, so they are only right
when nobody can reach qlang without going through the proxy.

```
app.use(redirect_to_https())                 -- http:// requests get a 301 to https://
let ip = client_ip(req)                      -- the visitor's address, not the proxy's
if is_https(req) then ... end
```

Turn on the `Secure` attribute of the session cookie (`Options { secure: true }`) when the site is
served in HTTPS only.
--"
import "app.q" as web

--" The scheme the visitor used (`https` or `http`), as the proxy says it; `http` without the header. --"
fun scheme(req: Request) -> string
  let proto = req.header("x-forwarded-proto")
  if proto == none then
    return "http"
  end
  -- several proxies in a row: the first one saw the visitor
  let first = proto.split(",")[0].trim().lower()
  if first == "https" then "https" else "http" end
end

fun is_https(req: Request) -> bool
  scheme(req) == "https"
end

--" The address of the visitor: the first one of `X-Forwarded-For`, or `none` without the header. --"
fun client_ip(req: Request) -> string?
  let forwarded = req.header("x-forwarded-for")
  if forwarded == none then
    return none
  end
  let first = forwarded.split(",")[0].trim()
  if first.is_empty() then none else first end
end

--" The host the visitor asked for (`X-Forwarded-Host`, else `Host`). --"
fun host(req: Request) -> string?
  req.header("x-forwarded-host") ?? req.header("host")
end

--" Sends a `301` to the `https://` address of every request the proxy received in plain HTTP. A
request that did not come through a proxy (no `X-Forwarded-Proto`) is left alone, so that
the program still works on your machine. --"
fun redirect_to_https() -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    let proto = req.header("x-forwarded-proto")
    if proto != none and not is_https(req) then
      let h = host(req)
      if h != none then
        return Response.redirect("https://{h}{req.url}").with_status(301)
      end
    end
    next(req)
  end
end

export scheme, is_https, client_ip, host, redirect_to_https

--" # Authentication with tokens

Guards for routes that are called with a **bearer token** (`Authorization: Bearer <jwt>`): mobile apps, single
page applications, other servers. (For a site with pages, use the cookie sessions of `session.q`.)

```
let keys = [jwt.Key.hs256(env.get("JWT_SECRET") ?? "")]
app.guard("jwt", jwt_guard(keys, jwt.Options { issuer: "https://api.example" }))
app.guard("admin", scope_guard(["admin"]))

#[web.Get("/me")]
#[web.Guard("jwt")]
fun me(req: Request) -> Profile
  let claims = claims_of<Session>(req)
  ...
end

#[web.Delete("/users/:id")]
#[web.Guard("jwt")]
#[web.Guard("admin")]          -- the guards run in this order: first the token, then the scope
fun remove(#[web.Path] id: int) -> Response ...
```

A guard that refuses answers `401` with `WWW-Authenticate: Bearer` (and `error="invalid_token"` when a
token was given), or `403` with `error="insufficient_scope"`, as RFC 6750 asks. The message does not say why
a token was refused (the log does).

To check the tokens of an identity provider, read its keys with `fetch_jwks(url, cache, 3600)`: the document
is fetched once an hour and kept in the cache, and the `kid` of each token picks the key.
--"
import "app.q" as web
import "cache.q" as cc
import "../jwt.q" as jwt

fun challenge(code: string?, detail: string) -> string
  let c = code
  if c == none then
    return "Bearer"
  end
  "Bearer error=\"{c}\"{detail}"
end

fun refuse(status: int, message: string, www: string) -> Response
  let res = web.Problem { status: status, message: message }.to_response()
  res.headers["WWW-Authenticate"] = www
  res
end

--" Lets through the requests with a valid token: its signature and its dates are checked with `keys` and
`options`. The token is kept for the route (`token_of`, `claims_of`). --"
fun jwt_guard(keys: array<jwt.Key>, options: jwt.Options) -> web.GuardFn
  fun(req: Request) -> Response?
    let header = req.header("authorization")
    if header == none or not header.lower().starts_with("bearer ") then
      return refuse(401, "Unauthorized", challenge(none, ""))
    end
    let text = header.substring(7, header.len()).trim()
    let checked = jwt.verify(text, keys, options)
    if checked.is_err() then
      Log.warning("token refused: {checked.unwrap_err().message}")
      return refuse(401, "Unauthorized", challenge("invalid_token", ""))
    end
    req.attrs["jwt"] = Any.of(checked.unwrap())
    none
  end
end

--" The token a `jwt_guard` accepted for this request. --"
fun token_of(req: Request) -> jwt.Token?
  let held = req.attrs["jwt"]
  if held == none then
    return none
  end
  held.as<jwt.Token>()
end

--" The claims of that token, read as a structure of yours. --"
fun claims_of<T>(req: Request) -> T?
  let token = token_of(req)
  if token == none then
    return none
  end
  let read = token.claims<T>()
  if read.is_err() then
    return none
  end
  read.unwrap()
end

--" Lets through the tokens that have **all** of these permissions (`scope: "read write"`, or a list in
`scopes` or `permissions`); the others get `403`. Put it after `jwt_guard`. --"
fun scope_guard(required: array<string>) -> web.GuardFn
  fun(req: Request) -> Response?
    let token = token_of(req)
    if token == none then
      return refuse(401, "Unauthorized", challenge(none, ""))
    end
    let have = token.scopes()
    for r in required do
      if not have.contains(r) then
        return refuse(403, "Forbidden", challenge("insufficient_scope", ", scope=\"{required.join(" ")}\""))
      end
    end
    none
  end
end

--" The keys of the JWKS published at `url`, kept `ttl` seconds in the cache. --"
fun fetch_jwks(url: string, cache: cc.Cache, ttl: int) -> Result<array<jwt.Key>, Error>
  let name = "jwks:{url}"
  let kept = cache.get_text(name)
  if kept != none then
    let keys = jwt.keys_from_jwks(kept)
    if keys.is_ok() then
      return keys
    end
  end
  let res = http.send(Request { method: "GET", url: url })
  if res.is_err() then
    return Result<array<jwt.Key>, Error>.Err(res.unwrap_err())
  end
  let answer = res.unwrap()
  if answer.status != 200 then
    return Result<array<jwt.Key>, Error>.Err(Error { message: "the JWKS answered {answer.status}" })
  end
  let keys = jwt.keys_from_jwks(answer.body)
  if keys.is_ok() then
    cache.put_text(name, answer.body, ttl)
  end
  keys
end

export jwt_guard, scope_guard, token_of, claims_of, fetch_jwks

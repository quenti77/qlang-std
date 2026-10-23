--" # Sessions in a signed cookie

What the user did earlier (who is logged in, a message to show once) kept between two requests,
without a server-side store: the data travels in a cookie, signed with a secret so that the
browser cannot change it. (It is signed, not hidden: do not put secrets in it. It is also limited
to about 3 KB, and it is not shared with other devices.)

```
app.use(sessions(secret))                   -- a long secret that only the server knows

#[web.Post("/login")]
fun login(req: Request) -> Response
  let s = session_of(req)
  s.set("user", "ada")
  Response.redirect("/")
end
```

`session_of(req)` gives the session of the request (an empty one for a new visitor). For a handler
parameter `s: Session`, add `session_of` to the providers: `app.container.provide(Reflect.callable(sessions_module, "session_of"))`.
Changes are written in the cookie of the response by the middleware.

CSRF: `csrf_protect()` refuses (`403`) a `POST`, `PUT`, `PATCH` or `DELETE` that does not repeat
the token of the session in the header `X-CSRF-Token` or in the form field `_csrf`; give the
token to the page with `session.csrf_token()`.
--"
import "app.q" as web
import "container.q" as di

--" The data of one visitor. --"
struct Session
  public data: map<string, string>
  public changed: bool
  public fresh: bool
end

impl Session
  --" A value, or `none`. --"
  public fun get(self, key: string) -> string?
    self.data[key]
  end

  --" Remembers a value. --"
  public fun set(self, key: string, value: string)
    self.data[key] = value
    self.changed = true
  end

  --" Forgets a value. --"
  public fun remove(self, key: string)
    if self.data[key] != none then
      self.data.remove(key)
      self.changed = true
    end
  end

  --" Forgets everything (log out). --"
  public fun clear(self)
    self.data = {}
    self.changed = true
  end

  --" A message for the next request only (`"Saved"` after a form): read it with `flash`. --"
  public fun flash_set(self, message: string)
    self.set("_flash", message)
  end

  --" The message left by the previous request, and forgets it. --"
  public fun flash(self) -> string?
    let m = self.data["_flash"]
    if m != none then
      self.remove("_flash")
    end
    m
  end

  --" The token that pages must send back with a form (made the first time). --"
  public fun csrf_token(self) -> string
    let t = self.data["_csrf"]
    if t != none then
      return t
    end
    let made = Crypto.token(24)
    let token = if made.is_ok() then made.unwrap() else "unavailable" end
    self.set("_csrf", token)
    token
  end
end

fun sign(secret: string, payload: string) -> string
  Hash.hmac_sha256(secret, payload)
end

fun encode(secret: string, data: map<string, string>) -> string
  let payload = Base64.encode_url(Json.of(data).to_text())
  "{payload}.{sign(secret, payload)}"
end

fun decode(secret: string, cookie: string) -> map<string, string>?
  let dot = cookie.last_index_of(".")
  if dot == none then
    return none
  end
  let payload = cookie.substring(0, dot)
  let given = cookie.substring(dot + 1, cookie.len())
  if not Crypto.equal(given, sign(secret, payload)) then
    return none
  end
  let text = Base64.decode(payload)
  if text == none then
    return none
  end
  let json = Json.parse(text)
  if json.is_err() then
    return none
  end
  let read = Json.to<map<string, string>>(json.unwrap())
  if read.is_err() then
    return none
  end
  read.unwrap()
end

--" The session of this request (`sessions` middleware must be in use). --"
fun session_of(req: Request) -> Session
  let held = req.attrs["session"]
  if held != none then
    let s = held.as<Session>()
    if s != none then
      return s
    end
  end
  Session { data: {}, changed: false, fresh: true }
end

--" Loads the session from the cookie `qs` (signed with `secret`) and writes it back when it
changed. The cookie is `HttpOnly` and `SameSite=Lax`; give `secure: true` behind HTTPS. --"
fun sessions(secret: string) -> web.Middleware
  sessions_with(secret, false)
end

--" Like `sessions`, with the `Secure` attribute of the cookie as you choose it. --"
fun sessions_with(secret: string, secure: bool) -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    let cookie = req.cookies["qs"]
    let loaded = if cookie == none then none else decode(secret, cookie) end
    let s = Session { data: if loaded == none then {} else loaded end, changed: false, fresh: loaded == none }
    req.attrs["session"] = Any.of(s)
    let res = next(req)
    if s.changed then
      let value = encode(secret, s.data)
      if value.len() <= 3800 then
        res.cookies.push(Cookie { name: "qs", value: value, secure: secure, same_site: "Lax" })
      else
        Log.error("the session is too big for a cookie and was not saved")
      end
    end
    res
  end
end

--" Refuses the unsafe requests that do not carry the token of the session. --"
fun csrf_protect() -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    if ["GET", "HEAD", "OPTIONS"].contains(req.method) then
      return next(req)
    end
    let s = session_of(req)
    let expected = s.get("_csrf")
    let given = req.header("x-csrf-token")
    if given == none then
      let form = req.form()
      if form.is_ok() then
        given = form.unwrap()["_csrf"]
      end
    end
    if expected == none or given == none or not Crypto.equal(expected, given) then
      return web.Problem { status: 403, message: "invalid CSRF token" }.to_response()
    end
    next(req)
  end
end

export Session, session_of, sessions, sessions_with, csrf_protect

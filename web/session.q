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

  --" The token that pages must send back with a form (made the first time). It panics if the
  system has no secure randomness: a token anyone could guess would protect nothing. --"
  public fun csrf_token(self) -> string
    let t = self.data["_csrf"]
    if t != none then
      return t
    end
    let token = Crypto.token(24).unwrap()
    self.set("_csrf", token)
    token
  end

  --" The hidden field to put in a form: `<input type="hidden" name="_csrf" value="...">`. --"
  public fun csrf_field(self) -> string
    "<input type=\"hidden\" name=\"_csrf\" value=\"{self.csrf_token()}\">"
  end

  --" A new identity for this visitor: call it when the user signs in or out, so that a token or
  an identifier seen before cannot be used with the new session (session fixation). The CSRF token
  changes too. --"
  public fun regenerate(self)
    self.data.remove("_csrf")
    self.data["_sid"] = Crypto.token(12).unwrap()
    self.changed = true
  end

  --" An identifier of this session, stable until `regenerate` (usable as a key for logs or a
  cache). --"
  public fun id(self) -> string
    let known = self.data["_sid"]
    if known != none then
      return known
    end
    let made = Crypto.token(12).unwrap()
    self.set("_sid", made)
    made
  end

  --" Keeps what the user typed in a form for the next request only, to show it again after a
  validation error (redirect to the form, then `old("title")`). Fields called `password...`, `_csrf` or
  `secret...` are left out. --"
  public fun flash_input(self, fields: map<string, string>)
    let kept: map<string, string> = {}
    for name in fields.keys() do
      let lowered = name.lower()
      if lowered.starts_with("password") or lowered.starts_with("secret") or lowered == "_csrf" then
        continue
      end
      kept[name] = fields[name] ?? ""
    end
    self.set("_old_next", Json.of(kept).to_text())
  end

  --" A field of the previous request's form (see `flash_input`), or `none`. --"
  public fun old(self, name: string) -> string?
    let held = self.data["_old"]
    if held == none then
      return none
    end
    let parsed = Json.parse(held)
    if parsed.is_err() then
      return none
    end
    let read = Json.to<map<string, string>>(parsed.unwrap())
    if read.is_err() then
      return none
    end
    read.unwrap()[name]
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

--" How long a session lives and how its cookie is sent. --"
struct Options
  --" The `Secure` attribute: the cookie only travels over HTTPS. Turn it on behind HTTPS. --"
  public secure: bool = false
  --" Seconds without activity after which the session is forgotten (2 hours). The signed cookie
  carries its own expiry, so an old cookie that was copied stops working. --"
  public lifetime: int = 7200
  --" `Lax` (the default: not sent with requests another site starts, except links), `Strict` or `None`. --"
  public same_site: string = "Lax"
end

--" Loads the session from the cookie `qs` (signed with `secret`) and writes it back when it
changed. The cookie is `HttpOnly` and `SameSite=Lax`, and the session ends after two hours without
activity; give `secure: true` behind HTTPS (`sessions_with`), or choose the lifetime (`sessions_using`). --"
fun sessions(secret: string) -> web.Middleware
  sessions_using(secret, Options {})
end

--" Like `sessions`, with the `Secure` attribute of the cookie as you choose it. --"
fun sessions_with(secret: string, secure: bool) -> web.Middleware
  sessions_using(secret, Options { secure: secure })
end

--" Like `sessions`, with the options you choose. --"
fun sessions_using(secret: string, options: Options) -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    let now = time.now()
    let cookie = req.cookies["qs"]
    let loaded = if cookie == none then none else decode(secret, cookie) end
    let data: map<string, string> = if loaded == none then {} else loaded end
    let stamp = int.parse(data["_exp"] ?? "")
    -- a cookie older than its expiry is a stranger; one without expiry (from before) is stamped now
    if stamp != none and stamp < now then
      data = {}
      loaded = none
    end
    let s = Session { data: data, changed: false, fresh: loaded == none }
    -- what the previous request left for this one only
    if s.data["_old_next"] != none then
      s.data["_old"] = s.data["_old_next"] ?? ""
      s.data.remove("_old_next")
      s.changed = true
    else
      if s.data["_old"] != none then
        s.data.remove("_old")
        s.changed = true
      end
    end
    req.attrs["session"] = Any.of(s)
    let res = next(req)
    let renew = stamp == none or stamp - now < options.lifetime * 500
    if not s.data.is_empty() and renew then
      s.changed = true
    end
    if s.changed and not s.data.is_empty() then
      s.data["_exp"] = "{now + options.lifetime * 1000}"
      let value = encode(secret, s.data)
      if value.len() <= 3800 then
        res.cookies.push(Cookie { name: "qs", value: value, secure: options.secure, same_site: options.same_site, max_age: options.lifetime })
      else
        Log.error("the session is too big for a cookie and was not saved")
      end
    else
      if s.changed then
        -- everything was forgotten: end the cookie
        res.cookies.push(Cookie { name: "qs", value: "", secure: options.secure, same_site: options.same_site, max_age: 0 })
      end
    end
    res
  end
end

--" Refuses the unsafe requests that do not carry the token of the session. --"
fun csrf_protect() -> web.Middleware
  csrf_protect_except([])
end

--" Like `csrf_protect`, but leaves alone the requests whose path starts with one of `prefixes`:
an API for other programs (`"/api/"`, which authenticates with a token it sends itself) or a webhook
that another service calls (`"/webhooks/"`). Everything else needs the token. --"
fun csrf_protect_except(prefixes: array<string>) -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    if ["GET", "HEAD", "OPTIONS"].contains(req.method) then
      return next(req)
    end
    for p in prefixes do
      if req.path.starts_with(p) then
        return next(req)
      end
    end
    let s = session_of(req)
    let expected = s.get("_csrf")
    let given = req.header("x-csrf-token")
    if given == none then
      let form = req.form()
      if form.is_ok() then
        given = form.unwrap()["_csrf"]
      else
        -- a form with files carries the field as one of its parts
        let parts = req.multipart()
        if parts.is_ok() then
          for part in parts.unwrap() do
            if part.name == "_csrf" and part.filename == none then
              given = part.text()
            end
          end
        end
      end
    end
    if expected == none or given == none or not Crypto.equal(expected, given) then
      return web.Problem { status: 403, message: "invalid CSRF token" }.to_response()
    end
    next(req)
  end
end

--" The usual protection of a site with forms, in one call: sessions with a signed cookie
(`HttpOnly`, `SameSite=Lax`, expiring) and the CSRF check. Give `secure: true` in `options` behind
HTTPS. The token is read from the header `X-CSRF-Token` or from the field `_csrf` of a form (a form
with files too). --"
fun protect(app: web.App, secret: string, options: Options)
  app.use(sessions_using(secret, options))
  app.use(csrf_protect())
end

export Session, Options, session_of, sessions, sessions_with, sessions_using, csrf_protect, csrf_protect_except, protect

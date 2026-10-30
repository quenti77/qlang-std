import "app.q" as web
import "cache.q" as cache
import "session.q" as sess
import "testing.q" as testing

fun build(secret: string) -> web.App
  let app = web.App.new([])
  app.use(sess.sessions(secret))
  app.use(sess.csrf_protect())
  app.get("/visit", fun(r: Request) -> Response
    let s = sess.session_of(r)
    let n = s.get("n")
    let count = 1
    if n != none then
      let parsed = n.to_int()
      if parsed != none then
        count = parsed
      end
    end
    s.set("n", "{count + 1}")
    Response.text("visit {count}")
  end)
  app.get("/token", fun(r: Request) -> Response Response.text(sess.session_of(r).csrf_token()) end)
  app.post("/save", fun(r: Request) -> Response Response.text("saved") end)
  app
end

fun req(method: string, path: string) -> Request
  Request { method: method, url: path, path: path }
end

fun cookie_of(res: Response) -> Cookie
  res.cookies[0]
end

fun test_a_session_is_kept_between_requests_by_its_signed_cookie()
  let app = build("secret")
  let first = app.handle(req("GET", "/visit"))
  assert_eq(first.body, "visit 1")
  assert_eq(first.cookies.len(), 1)
  let c = cookie_of(first)
  assert(c.http_only)
  let again = req("GET", "/visit")
  again.cookies["qs"] = c.value
  let second = app.handle(again)
  assert_eq(second.body, "visit 2")
end

fun test_a_changed_cookie_or_another_secret_starts_a_new_session()
  let app = build("secret")
  let c = cookie_of(app.handle(req("GET", "/visit")))
  let forged = req("GET", "/visit")
  forged.cookies["qs"] = c.value.replace("e", "f")
  assert_eq(app.handle(forged).body, "visit 1")
  let other = build("another")
  let again = req("GET", "/visit")
  again.cookies["qs"] = c.value
  assert_eq(other.handle(again).body, "visit 1")
end

fun test_an_unchanged_session_sets_no_cookie()
  let app = build("secret")
  let r = app.handle(req("GET", "/token"))
  -- the token was just made, so the session did change
  assert(r.cookies.len() == 1)
  let c = cookie_of(r)
  let next = req("GET", "/token")
  next.cookies["qs"] = c.value
  assert_eq(app.handle(next).cookies.len(), 0)
end

fun test_unsafe_requests_need_the_csrf_token()
  let app = build("secret")
  let t = app.handle(req("GET", "/token"))
  let cookie = cookie_of(t).value
  let none_sent = req("POST", "/save")
  none_sent.cookies["qs"] = cookie
  assert_eq(app.handle(none_sent).status, 403)
  let wrong = req("POST", "/save")
  wrong.cookies["qs"] = cookie
  wrong.headers["x-csrf-token"] = "nope"
  assert_eq(app.handle(wrong).status, 403)
  let good = req("POST", "/save")
  good.cookies["qs"] = cookie
  good.headers["x-csrf-token"] = t.body
  assert_eq(app.handle(good).body, "saved")
  let form = req("POST", "/save")
  form.cookies["qs"] = cookie
  form.headers["content-type"] = "application/x-www-form-urlencoded"
  form.body = "_csrf=" + Url.encode(t.body)
  assert_eq(app.handle(form).body, "saved")
  assert_eq(app.handle(req("POST", "/save")).status, 403)
end

fun test_flash_messages_are_read_once()
  let s = sess.Session { data: {}, changed: false, fresh: true }
  s.flash_set("Saved")
  assert_eq(s.flash(), "Saved")
  assert_eq(s.flash(), none)
end

-- a signed cookie as the middleware would write it, with the data we choose
fun forge(secret: string, data: map<string, string>) -> string
  let payload = Base64.encode_url(Json.of(data).to_text())
  "{payload}.{Hash.hmac_sha256(secret, payload)}"
end

fun test_the_cookie_expires_and_an_old_one_is_not_accepted()
  let app = build("secret")
  let first = app.handle(req("GET", "/visit"))
  let c = cookie_of(first)
  assert_eq(c.max_age, 7200)
  -- a cookie whose own expiry is in the past is a stranger, even with a good signature
  let stale = req("GET", "/visit")
  stale.cookies["qs"] = forge("secret", {"n": "9", "_exp": "1000"})
  assert_eq(app.handle(stale).body, "visit 1")
  -- one that is still valid is kept
  let live = req("GET", "/visit")
  live.cookies["qs"] = forge("secret", {"n": "9", "_exp": "{time.now() + 3600000}"})
  assert_eq(app.handle(live).body, "visit 9")
  -- one from before the expiry existed is accepted once and stamped
  let old = req("GET", "/visit")
  old.cookies["qs"] = forge("secret", {"n": "4"})
  let answered = app.handle(old)
  assert_eq(answered.body, "visit 4")
  assert_eq(answered.cookies.len(), 1)
end

fun test_the_options_choose_lifetime_secure_and_same_site()
  let app = web.App.new([])
  app.use(sess.sessions_using("s", sess.Options { secure: true, lifetime: 60, same_site: "Strict" }))
  app.get("/", fun(r: Request) -> Response
    sess.session_of(r).set("a", "b")
    Response.text("ok")
  end)
  let c = cookie_of(app.handle(req("GET", "/")))
  assert(c.secure)
  assert_eq(c.max_age, 60)
  assert_eq(c.same_site, "Strict")
  assert(c.http_only)
end

fun test_clearing_the_session_ends_the_cookie()
  let app = web.App.new([])
  app.use(sess.sessions("s"))
  app.get("/in", fun(r: Request) -> Response
    sess.session_of(r).set("a", "b")
    Response.text("in")
  end)
  app.get("/out", fun(r: Request) -> Response
    sess.session_of(r).clear()
    Response.text("out")
  end)
  let c = cookie_of(app.handle(req("GET", "/in")))
  let leave = req("GET", "/out")
  leave.cookies["qs"] = c.value
  let ended = cookie_of(app.handle(leave))
  assert_eq(ended.max_age, 0)
end

fun test_regenerate_changes_the_token_and_the_identifier()
  let app = web.App.new([])
  app.use(sess.sessions("s"))
  app.get("/token", fun(r: Request) -> Response
    let s = sess.session_of(r)
    Response.text("{s.id()} {s.csrf_token()}")
  end)
  app.get("/login", fun(r: Request) -> Response
    let s = sess.session_of(r)
    s.regenerate()
    Response.text("{s.id()} {s.csrf_token()}")
  end)
  let first = app.handle(req("GET", "/token"))
  let again = req("GET", "/login")
  again.cookies["qs"] = cookie_of(first).value
  let after = app.handle(again)
  assert(first.body != after.body)
  assert(first.body.split(" ")[0] != after.body.split(" ")[0])
  assert(first.body.split(" ")[1] != after.body.split(" ")[1])
end

fun test_a_form_field_for_the_csrf_token()
  let app = web.App.new([])
  app.use(sess.sessions("s"))
  app.get("/", fun(r: Request) -> Response Response.text(sess.session_of(r).csrf_field()) end)
  let body = app.handle(req("GET", "/")).body
  assert(body.starts_with("<input type=\"hidden\" name=\"_csrf\" value=\""))
  assert(body.ends_with("\">"))
end

fun test_what_the_user_typed_comes_back_once_without_the_password()
  let app = web.App.new([])
  app.use(sess.sessions("s"))
  app.post("/save", fun(r: Request) -> Response
    sess.session_of(r).flash_input({"title": "Hello", "password": "hunter2", "_csrf": "x"})
    Response.redirect("/form")
  end)
  app.get("/form", fun(r: Request) -> Response
    let s = sess.session_of(r)
    Response.text("{s.old("title") ?? "-"}/{s.old("password") ?? "-"}")
  end)
  let sent = app.handle(req("POST", "/save"))
  assert_eq(sent.status, 302)
  let show = req("GET", "/form")
  show.cookies["qs"] = cookie_of(sent).value
  let shown = app.handle(show)
  assert_eq(shown.body, "Hello/-")
  -- the next request no longer has it
  let third = req("GET", "/form")
  third.cookies["qs"] = cookie_of(shown).value
  assert_eq(app.handle(third).body, "-/-")
end

fun test_csrf_can_leave_some_paths_alone()
  let app = web.App.new([])
  app.use(sess.sessions("s"))
  app.use(sess.csrf_protect_except(["/webhooks/"]))
  app.post("/webhooks/pay", fun(r: Request) -> Response Response.text("paid") end)
  app.post("/form", fun(r: Request) -> Response Response.text("form") end)
  assert_eq(app.handle(req("POST", "/webhooks/pay")).status, 200)
  assert_eq(app.handle(req("POST", "/form")).status, 403)
end

fun test_protect_sets_up_sessions_and_csrf_together()
  let app = web.App.new([])
  sess.protect(app, "s", sess.Options {})
  app.post("/form", fun(r: Request) -> Response Response.text("form") end)
  app.get("/token", fun(r: Request) -> Response Response.text(sess.session_of(r).csrf_token()) end)
  assert_eq(app.handle(req("POST", "/form")).status, 403)
  let t = app.handle(req("GET", "/token"))
  let ok = req("POST", "/form")
  ok.cookies["qs"] = cookie_of(t).value
  ok.headers["x-csrf-token"] = t.body
  assert_eq(app.handle(ok).status, 200)
end

fun test_the_csrf_field_of_a_form_with_files_is_read()
  let app = web.App.new([])
  sess.protect(app, "s", sess.Options {})
  app.post("/upload", fun(r: Request) -> Response Response.text("stored") end)
  app.get("/token", fun(r: Request) -> Response Response.text(sess.session_of(r).csrf_token()) end)
  let client = testing.Client.new(app)
  let t = client.get("/token")
  let file = testing.TestFile { field: "doc", filename: "a.txt", content_type: "text/plain", data: "hi".to_bytes() }
  client.post_multipart("/upload", {}, [file]).expect_status(403)
  client.post_multipart("/upload", {"_csrf": t.body}, [file]).expect_status(200)
end

fun stored_app(store: cache.Store) -> web.App
  let app = web.App.new([])
  app.use(sess.sessions_using("secret", sess.Options { store: store }))
  app.get("/visit", fun(r: Request) -> Response
    let s = sess.session_of(r)
    let n = int.parse(s.get("n") ?? "0") ?? 0
    s.set("n", "{n + 1}")
    Response.text("visit {n + 1}")
  end)
  app.get("/login", fun(r: Request) -> Response
    let s = sess.session_of(r)
    s.set("user", "ada")
    s.regenerate()
    Response.text("in")
  end)
  app.get("/logout", fun(r: Request) -> Response
    sess.session_of(r).clear()
    Response.text("out")
  end)
  app.get("/who", fun(r: Request) -> Response Response.text(sess.session_of(r).get("user") ?? "nobody") end)
  app
end

fun with_cookie(path: string, value: string) -> Request
  let r = req("GET", path)
  r.cookies["qs"] = value
  r
end

fun test_a_server_side_session_only_puts_a_signed_identifier_in_the_cookie()
  let store = cache.MemoryStore.new()
  let app = stored_app(store)
  let first = app.handle(req("GET", "/visit"))
  let c = cookie_of(first)
  assert(not c.value.contains("eyJ"))
  assert_eq(c.max_age, 7200)
  assert_eq(app.handle(with_cookie("/visit", c.value)).body, "visit 2")
  -- a cookie whose signature is wrong is a stranger
  let id = c.value.substring(0, c.value.last_index_of(".") ?? 0)
  assert_eq(app.handle(with_cookie("/visit", id + ".forged")).body, "visit 1")
  assert_eq(app.handle(with_cookie("/visit", "{id}")).body, "visit 1")
end

fun test_the_data_is_shared_by_every_worker_that_shares_the_store()
  let store = cache.MemoryStore.new()
  let one = stored_app(store)
  let two = stored_app(store)
  let c = cookie_of(one.handle(req("GET", "/visit")))
  assert_eq(two.handle(with_cookie("/visit", c.value)).body, "visit 2")
  assert_eq(one.handle(with_cookie("/visit", c.value)).body, "visit 3")
end

fun test_regenerate_gives_a_new_identifier_and_the_old_one_stops_working()
  let store = cache.MemoryStore.new()
  let app = stored_app(store)
  let before = cookie_of(app.handle(req("GET", "/visit")))
  let after = cookie_of(app.handle(with_cookie("/login", before.value)))
  assert(after.value != before.value)
  assert_eq(app.handle(with_cookie("/who", after.value)).body, "ada")
  assert_eq(app.handle(with_cookie("/who", before.value)).body, "nobody")
end

fun test_clearing_ends_the_session_on_the_server()
  let store = cache.MemoryStore.new()
  let app = stored_app(store)
  let c = cookie_of(app.handle(with_cookie("/login", cookie_of(app.handle(req("GET", "/visit"))).value)))
  let out = app.handle(with_cookie("/logout", c.value))
  assert_eq(cookie_of(out).max_age, 0)
  assert_eq(app.handle(with_cookie("/who", c.value)).body, "nobody")
end

fun test_sessions_can_live_in_a_database()
  let db = Db.connect("sqlite://:memory:").unwrap()
  let store = cache.DbStore.new(db, "sessions")
  store.install().unwrap()
  let app = stored_app(store)
  let c = cookie_of(app.handle(req("GET", "/visit")))
  assert_eq(app.handle(with_cookie("/visit", c.value)).body, "visit 2")
  assert_eq(db.query("SELECT k FROM sessions", []).unwrap().len(), 1)
end

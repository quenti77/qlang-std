import "app.q" as web
import "session.q" as sess

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

import "app.q" as web
import "middleware.q" as mw

fun app_with(m: web.Middleware) -> web.App
  let app = web.App.new([])
  app.use(m)
  app.get("/hi", fun(r: Request) -> Response Response.text("hi") end)
  app
end

fun req(method: string, path: string) -> Request
  Request { method: method, url: path, path: path }
end

fun test_security_headers_are_added_but_never_override()
  let app = web.App.new([])
  app.use(mw.security_headers())
  app.get("/hi", fun(r: Request) -> Response Response.text("hi").with_header("X-Frame-Options", "SAMEORIGIN") end)
  let r = app.handle(req("GET", "/hi"))
  assert_eq(r.headers["X-Content-Type-Options"], "nosniff")
  assert_eq(r.headers["X-Frame-Options"], "SAMEORIGIN")
  assert_eq(r.headers["Referrer-Policy"], "same-origin")
end

fun test_cors_answers_the_preflight_and_marks_the_other_answers()
  let app = app_with(mw.cors(["https://app.example"]))
  let pre = req("OPTIONS", "/hi")
  pre.headers["origin"] = "https://app.example"
  pre.headers["access-control-request-method"] = "POST"
  let r = app.handle(pre)
  assert_eq(r.status, 204)
  assert_eq(r.headers["Access-Control-Allow-Origin"], "https://app.example")
  let get = req("GET", "/hi")
  get.headers["origin"] = "https://app.example"
  assert_eq(app.handle(get).headers["Access-Control-Allow-Origin"], "https://app.example")
  let other = req("GET", "/hi")
  other.headers["origin"] = "https://evil.example"
  assert(app.handle(other).headers["Access-Control-Allow-Origin"] == none)
  assert(app.handle(req("GET", "/hi")).headers["Access-Control-Allow-Origin"] == none)
end

fun test_a_bearer_token_is_required_and_checked()
  let app = app_with(mw.bearer_token(fun(t: string) -> bool Crypto.equal(t, "s3cret") end))
  assert_eq(app.handle(req("GET", "/hi")).status, 401)
  let bad = req("GET", "/hi")
  bad.headers["authorization"] = "Bearer nope"
  assert_eq(app.handle(bad).status, 401)
  let good = req("GET", "/hi")
  good.headers["authorization"] = "Bearer s3cret"
  assert_eq(app.handle(good).status, 200)
  assert_eq(app.handle(req("GET", "/hi")).headers["WWW-Authenticate"], "Bearer")
end

fun test_each_request_gets_an_id()
  let app = app_with(mw.request_id())
  let r = app.handle(req("GET", "/hi"))
  assert(r.headers["X-Request-Id"] != none)
  let given = req("GET", "/hi")
  given.headers["x-request-id"] = "abc-123"
  assert_eq(app.handle(given).headers["X-Request-Id"], "abc-123")
end

fun test_logging_does_not_change_the_answer()
  let app = app_with(mw.logging())
  assert_eq(app.handle(req("GET", "/hi")).body, "hi")
  assert_eq(app.handle(req("GET", "/missing")).status, 404)
end

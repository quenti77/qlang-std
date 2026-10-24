import "app.q" as web
import "middleware.q" as mw
import "testing.q" as testing
import "test_blog.q" as blog
import "test_blog_controllers.q" as controllers

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

fun test_cors_options_shape_the_preflight_and_the_answers()
  let app = web.App.new(Reflect.callables(blog))
  app.controllers(Reflect.callables(controllers))
  app.use(mw.cors_with(mw.CorsOptions { origins: ["https://a.example"], methods: ["GET"], headers: ["X-Token"], expose: ["X-Request-Id"], credentials: true, max_age: 30 }))
  let client = testing.Client.new(app)
  client.header("Origin", "https://a.example")
  let ok = client.get("/posts")
  assert_eq(ok.header("access-control-allow-origin"), "https://a.example")
  assert_eq(ok.header("access-control-allow-credentials"), "true")
  assert_eq(ok.header("access-control-expose-headers"), "X-Request-Id")
  client.header("Access-Control-Request-Method", "GET")
  let pre = client.send("OPTIONS", "/posts", none)
  assert_eq(pre.status, 204)
  assert_eq(pre.header("access-control-allow-methods"), "GET")
  assert_eq(pre.header("access-control-allow-headers"), "X-Token")
  assert_eq(pre.header("access-control-max-age"), "30")
  let other = testing.Client.new(app)
  other.header("Origin", "https://evil.example")
  assert_eq(other.get("/posts").header("access-control-allow-origin"), none)
end

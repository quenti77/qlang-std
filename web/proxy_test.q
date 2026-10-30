import "app.q" as web
import "proxy.q" as proxy

fun req(headers: map<string, string>) -> Request
  Request { method: "GET", url: "/a?b=1", path: "/a", headers: headers }
end

fun test_the_scheme_and_the_visitor_come_from_the_proxy_headers()
  let plain = req({})
  assert_eq(proxy.is_https(plain), false)
  assert_eq(proxy.client_ip(plain), none)
  let behind = req({"x-forwarded-proto": "https, http", "x-forwarded-for": "203.0.113.7, 10.0.0.2"})
  assert_eq(proxy.is_https(behind), true)
  assert_eq(proxy.client_ip(behind), "203.0.113.7")
  assert_eq(proxy.host(req({"host": "inner", "x-forwarded-host": "example.com"})), "example.com")
  assert_eq(proxy.host(req({"host": "inner"})), "inner")
end

fun test_plain_http_through_the_proxy_is_redirected_to_https()
  let app = web.App.new([])
  app.use(proxy.redirect_to_https())
  app.get("/a", fun(r: Request) -> Response Response.text("hello") end)
  let moved = app.handle(req({"x-forwarded-proto": "http", "host": "example.com"}))
  assert_eq(moved.status, 301)
  assert_eq(moved.headers["Location"], "https://example.com/a?b=1")
  assert_eq(app.handle(req({"x-forwarded-proto": "https", "host": "example.com"})).status, 200)
  -- not behind a proxy (development): left alone
  assert_eq(app.handle(req({"host": "localhost:8080"})).status, 200)
end

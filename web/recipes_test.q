import "app.q" as web
import "testing.q" as testing
import "test_recipes_routes.q" as routes

fun pretty_errors() -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    let res = next(req)
    let wants_html = (req.header("accept") ?? "").contains("text/html")
    if res.status >= 400 and wants_html then
      let page = Response.html("<h1>Error {res.status}</h1>")
      page.status = res.status
      return page
    end
    res
  end
end

fun build() -> web.App
  let app = web.App.new([])
  app.use(pretty_errors())
  app.prefix("/api")
  app.controllers(Reflect.callables(routes))
  app.prefix("")
  app.get("/health", fun(r: Request) -> Response Response.text("ok") end)
  app
end

fun test_redirects_html_and_files_are_plain_responses()
  let client = testing.Client.new(build())
  let moved = client.get("/api/old")
  assert_eq(moved.status, 302)
  assert_eq(moved.header("location"), "/new")
  assert((client.get("/api/page").header("content-type") ?? "").contains("text/html"))
  let file = client.get("/api/file")
  assert_eq(file.header("content-disposition") != none, true)
  assert_eq(file.cookies.len(), 1)
end

fun test_prefix_makes_a_group_and_can_be_reset()
  let client = testing.Client.new(build())
  client.get("/api/ping").expect_status(200)
  client.get("/ping").expect_status(404)
  client.get("/health").expect_status(200)
end

fun test_an_error_page_middleware_rewrites_failures_for_browsers()
  let client = testing.Client.new(build())
  assert(client.get("/api/boom").body.contains("\"error\""))
  client.header("Accept", "text/html")
  let page = client.get("/api/boom")
  assert_eq(page.status, 500)
  assert_eq(page.body, "<h1>Error 500</h1>")
  assert(not page.body.contains("db down"))
end

fun test_an_upload_is_read_part_by_part()
  let client = testing.Client.new(build())
  let body = "--XX\r\nContent-Disposition: form-data; name=\"note\"\r\n\r\nhello\r\n--XX\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nabc\r\n--XX--\r\n"
  client.header("Content-Type", "multipart/form-data; boundary=XX")
  let r = client.post("/api/upload", body).expect_status(200)
  assert_eq(r.body, "note:-:5,doc:a.txt:3")
end

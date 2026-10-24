import "app.q" as web
import "testing.q" as testing
import "test_blog.q" as blog
import "test_blog_controllers.q" as controllers
import "session.q" as sess

fun build() -> web.App
  let app = web.App.new(Reflect.callables(blog))
  app.controllers(Reflect.callables(controllers))
  app
end

fun test_a_client_sends_requests_without_a_server()
  let client = testing.Client.new(build())
  let r = client.get("/posts/2")
  r.expect_status(200)
  assert_eq(r.header("content-type") != none, true)
  assert(r.body.contains("Second"))
end

fun test_a_query_string_is_read_like_the_server_reads_it()
  let client = testing.Client.new(build())
  assert(not client.get("/posts?limit=1").body.contains("Second"))
  client.get("/posts?limit=many").expect_status(400)
end

fun test_json_goes_in_and_comes_out_typed()
  let client = testing.Client.new(build())
  let made = client.post_json("/posts", blog.NewPost { title: "Third" })
  made.expect_status(201)
  let post = made.json<blog.Post>().unwrap()
  assert_eq(post.title, "Third")
  client.post_json("/posts", blog.NewPost { title: "x" }).expect_status(422)
end

fun test_default_headers_and_cookies_follow_the_requests()
  let client = testing.Client.new(build())
  client.header("X-Token", "abc")
  client.cookies["sid"] = "s1"
  assert_eq(client.get("/header").body, "abc/s1")
end

fun test_cookies_of_a_response_are_sent_back()
  let app = build()
  app.get("/set", fun(req: Request) -> Response
    Response.text("ok").with_cookie(Cookie { name: "seen", value: "yes" })
  end)
  app.get("/get", fun(req: Request) -> Response
    Response.text(req.cookies["seen"] ?? "no")
  end)
  let client = testing.Client.new(app)
  assert_eq(client.get("/get").body, "no")
  client.get("/set")
  assert_eq(client.get("/get").body, "yes")
  client.forget_cookies()
  assert_eq(client.get("/get").body, "no")
end

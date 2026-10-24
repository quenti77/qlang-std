import "app.q" as web
import "test_blog.q" as blog
import "test_blog_controllers.q" as controllers

fun build() -> web.App
  let app = web.App.new(Reflect.callables(blog))
  app.controllers(Reflect.callables(controllers))
  with_auth(app)
  app
end

fun req(method: string, path: string) -> Request
  let query: map<string, string> = {}
  let at = path.index_of("?")
  let clean = if at == none then path else path.substring(0, at) end
  if at != none then
    for pair in path.substring(at + 1, path.len()).split("&") do
      let kv = pair.split("=")
      query[kv[0]] = kv[1]
    end
  end
  Request { method: method, url: path, path: clean, query: query }
end

fun with_body(r: Request, body: string) -> Request
  r.body = body
  r
end

fun test_the_wiring_is_checked_before_the_first_request()
  assert_eq(build().validate(), [])
end

fun test_a_path_parameter_is_read_as_its_type_and_a_service_is_injected()
  let r = build().handle(req("GET", "/posts/2"))
  assert_eq(r.status, 200)
  assert_eq(r.body, "\{\"id\":2,\"title\":\"Second\"\}")
end

fun test_none_is_a_404_and_a_bad_parameter_a_400()
  let app = build()
  assert_eq(app.handle(req("GET", "/posts/99")).status, 404)
  let bad = app.handle(req("GET", "/posts/abc"))
  assert_eq(bad.status, 400)
  assert(bad.body.contains("path parameter id"))
end

fun test_a_query_parameter_may_be_absent_when_its_type_allows_it()
  let app = build()
  assert_eq(app.handle(req("GET", "/posts")).body.contains("Second"), true)
  let one = app.handle(req("GET", "/posts?limit=1"))
  assert(not one.body.contains("Second"))
  assert_eq(app.handle(req("GET", "/posts?limit=many")).status, 400)
end

fun test_a_body_is_decoded_validated_and_answered_with_its_status()
  let app = build()
  let ok = app.handle(with_body(req("POST", "/posts"), "\{\"title\": \"Third\"\}"))
  assert_eq(ok.status, 201)
  assert(ok.body.contains("Third"))
  let short = app.handle(with_body(req("POST", "/posts"), "\{\"title\": \"x\"\}"))
  assert_eq(short.status, 422)
  assert(short.body.contains("must have at least 3 characters or elements"))
  assert(short.body.contains("\"field\":\"title\""))
  assert_eq(app.handle(with_body(req("POST", "/posts"), "not json")).status, 400)
  assert_eq(app.handle(req("POST", "/posts")).status, 400)
  assert_eq(app.handle(with_body(req("POST", "/posts"), "\{\"title\": 5\}")).status, 422)
end

fun test_a_request_scoped_service_sees_its_own_request()
  let app = build()
  assert_eq(app.handle(req("GET", "/me")).body, "hello guest")
  let r = req("GET", "/me")
  r.headers["x-user"] = "ada"
  assert_eq(app.handle(r).body, "hello ada")
  assert_eq(app.handle(req("GET", "/me")).body, "hello guest")
end

fun test_headers_and_cookies_fill_parameters()
  let app = build()
  let r = req("GET", "/header")
  r.headers["x-token"] = "T"
  r.cookies["sid"] = "S"
  assert_eq(app.handle(r).body, "T/S")
  let r2 = req("GET", "/header")
  r2.headers["x-token"] = "T"
  assert_eq(app.handle(r2).body, "T/none")
  assert_eq(app.handle(req("GET", "/header")).status, 400)
end

fun test_errors_become_responses_without_leaking_details()
  let app = build()
  let teapot = app.handle(req("GET", "/fail/http"))
  assert_eq(teapot.status, 418)
  assert(teapot.body.contains("teapot"))
  let plain = app.handle(req("GET", "/fail/plain"))
  assert_eq(plain.status, 500)
  assert(not plain.body.contains("secret detail"))
end

fun test_no_value_is_a_204_and_a_response_is_sent_as_it_is()
  let app = build()
  assert_eq(app.handle(req("GET", "/nothing")).status, 204)
  assert_eq(app.handle(req("GET", "/raw")).body, "raw /raw")
end

fun test_unknown_paths_and_wrong_methods()
  let app = build()
  assert_eq(app.handle(req("GET", "/nope")).status, 404)
  let r = app.handle(req("DELETE", "/posts"))
  assert_eq(r.status, 405)
  assert(r.headers["Allow"] != none)
  assert_eq(app.handle(req("OPTIONS", "/any")).body, "options")
end

fun test_middleware_wrap_the_routes_the_first_one_outermost()
  let app = build()
  let log: array<string> = []
  app.use(fun(r: Request, next: web.Handler) -> Response
    log.push("a before")
    let res = next(r)
    log.push("a after")
    res
  end)
  app.use(fun(r: Request, next: web.Handler) -> Response
    log.push("b")
    if r.path == "/blocked" then
      return Response { status: 403, body: "no" }
    end
    next(r)
  end)
  assert_eq(app.handle(req("GET", "/raw")).body, "raw /raw")
  assert_eq(log, ["a before", "b", "a after"])
  assert_eq(app.handle(req("GET", "/blocked")).status, 403)
end

fun test_plain_functions_can_be_routes_too_and_a_prefix_applies()
  let app = build()
  app.prefix("/v2")
  app.get("/ping", fun(r: Request) -> Response Response.text("pong") end)
  assert_eq(app.handle(req("GET", "/v2/ping")).body, "pong")
  assert_eq(app.handle(req("GET", "/ping")).status, 404)
end

fun test_validate_finds_wiring_mistakes()
  let app = web.App.new([])
  app.controllers(Reflect.callables(controllers))
  let problems = app.validate()
  assert(problems.contains("GET /posts needs Posts: no provider"))
  assert(problems.contains("POST /posts needs Posts: no provider"))
end

fun test_validate_finds_a_route_hidden_by_an_earlier_one()
  let app = build()
  app.get("/posts/:id", fun(r: Request) -> Response Response.text("") end)
  app.get("/posts/new", fun(r: Request) -> Response Response.text("") end)
  let problems = app.validate()
  assert(problems.contains("GET /posts/:id is hidden by /posts/:id"))
  assert(problems.contains("GET /posts/new is hidden by /posts/:id"))
end

fun test_a_struct_with_annotated_methods_is_a_controller_under_its_prefix()
  let app = web.App.new(Reflect.callables(blog))
  app.controller(controllers.Shelf { label: "books" })
  assert_eq(app.validate(), [])
  let all = app.handle(req("GET", "/shelf"))
  assert_eq(all.status, 200)
  assert(all.body.starts_with("books: "))
  assert_eq(app.handle(req("GET", "/shelf/2")).status, 200)
  assert_eq(app.handle(req("GET", "/shelf/99")).status, 404)
  let made = app.handle(with_body(req("POST", "/shelf"), "\{\"title\": \"Fourth\"\}"))
  assert_eq(made.status, 201)
  assert_eq(app.handle(req("GET", "/not_a_route")).status, 404)
end

fun test_a_controller_may_come_from_the_container()
  let app = web.App.new(Reflect.callables(blog))
  app.controller_from_container<controllers.Shelf>()
  assert(app.validate().len() > 0)
end

fun with_auth(app: web.App)
  app.guard("auth", fun(req: Request) -> Response?
    let token = req.header("authorization")
    if token == none then
      return web.Problem { status: 401, message: "Unauthorized" }.to_response()
    end
    req.attrs["who"] = Any.of("ada")
    none
  end)
end

fun test_a_guard_stops_a_request_or_lets_it_through()
  let app = build()
  with_auth(app)
  assert_eq(app.handle(req("GET", "/secret")).status, 401)
  let ok = app.handle(Request { method: "GET", url: "/secret", path: "/secret", headers: {"authorization": "x"} })
  assert_eq(ok.status, 200)
  assert_eq(ok.body, "for ada")
  assert_eq(app.handle(req("GET", "/posts")).status, 200)
end

fun test_a_guard_on_a_controller_covers_its_routes()
  let app = build()
  with_auth(app)
  app.controller(controllers.Admin { tag: "x" })
  assert_eq(app.handle(req("GET", "/admin")).status, 401)
  let ok = app.handle(Request { method: "GET", url: "/admin", path: "/admin", headers: {"authorization": "x"} })
  assert_eq(ok.body, "admin x")
end

fun test_validate_finds_a_guard_nobody_defined()
  let bare = web.App.new(Reflect.callables(blog))
  bare.controllers(Reflect.callables(controllers))
  let found = bare.validate()
  assert(found.len() > 0)
  assert(found[0].contains("guard auth"))
end

fun test_a_form_body_is_read_like_json()
  let app = build()
  let sent = Request { method: "POST", url: "/posts", path: "/posts", headers: {"content-type": "application/x-www-form-urlencoded"}, body: "title=Fourth&stars=3" }
  let ok = app.handle(sent)
  assert_eq(ok.status, 201)
  assert(ok.body.contains("Fourth"))
  let short = Request { method: "POST", url: "/posts", path: "/posts", headers: {"content-type": "application/x-www-form-urlencoded"}, body: "title=x" }
  assert_eq(app.handle(short).status, 422)
  let bad = Request { method: "POST", url: "/posts", path: "/posts", headers: {"content-type": "application/x-www-form-urlencoded"}, body: "title=Fourth&stars=many" }
  assert_eq(app.handle(bad).status, 400)
end

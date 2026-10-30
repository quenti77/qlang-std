import "admin.q" as adm
import "app.q" as web
import "session.q" as sess
import "testing.q" as testing

fun make(allowed: bool, csrf: bool) -> testing.Client
  let db = Db.connect("sqlite://:memory:").unwrap()
  db.execute("CREATE TABLE posts (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT, rating REAL, published INTEGER NOT NULL DEFAULT 0, secret TEXT NOT NULL DEFAULT 'hidden')", []).unwrap()
  for i in 1..=5 do
    db.execute("INSERT INTO posts (title, body, rating) VALUES (?, ?, ?)", [Json.string("Post {i}"), Json.string("Body {i}"), Json.number(i as float)]).unwrap()
  end
  db.execute("INSERT INTO posts (title, body) VALUES (?, ?)", [Json.string("<script>alert(1)</script>"), Json.string("x")]).unwrap()
  let panel = adm.Admin.new(db, "Back office", [
    adm.Resource {
      name: "posts", table: "posts", title: "Posts", per_page: 4,
      columns: [
        adm.Column { name: "title", searchable: true, required: true },
        adm.Column { name: "body", kind: "textarea", searchable: true },
        adm.Column { name: "rating", kind: "number" },
        adm.Column { name: "published", kind: "bool" },
      ],
    },
    adm.Resource { name: "readonly", table: "posts", title: "Read only", can_create: false, can_edit: false, can_delete: false, columns: [adm.Column { name: "title" }] },
  ])
  panel.csrf = csrf
  let app = web.App.new([])
  app.use(sess.sessions("test secret test secret test secret"))
  let guard = fun(req: Request) -> Response?
    if allowed then none else web.Problem { status: 401, message: "sign in" }.to_response() end
  end
  adm.mount(app, panel, "/admin", guard)
  testing.Client.new(app)
end

fun jget(j: Json, key: string) -> Json
  assert_some(j.get(key))
end

fun api_token(client: testing.Client) -> string
  let r = client.get("/admin/api/csrf")
  jget(Json.parse(r.body).unwrap(), "token").as_string()
end

fun test_the_guard_protects_every_route()
  let client = make(false, true)
  for path in ["/admin", "/admin/posts", "/admin/posts/new", "/admin/posts/1/edit", "/admin/api/posts", "/admin/api/posts/1", "/admin/api/csrf"] do
    client.get(path).expect_status(401)
  end
  client.post("/admin/posts", "title=x").expect_status(401)
  client.send("DELETE", "/admin/api/posts/1", none).expect_status(401)
end

fun test_a_badly_declared_resource_stops_the_mount()
  let db = Db.connect("sqlite://:memory:").unwrap()
  let app = web.App.new([])
  let allow = fun(req: Request) -> Response? none end
  for bad in [
    adm.Resource { name: "api", table: "posts", title: "x", columns: [] },
    adm.Resource { name: "ok", table: "posts; DROP TABLE posts", title: "x", columns: [] },
    adm.Resource { name: "ok", table: "posts", title: "x", columns: [adm.Column { name: "a b" }] },
    adm.Resource { name: "ok", table: "posts", title: "x", columns: [adm.Column { name: "a", kind: "weird" }] },
    adm.Resource { name: "ok", table: "posts", title: "x", per_page: 500, columns: [] },
    ] do
    let failed = Panic.guard(fun() adm.mount(app, adm.Admin.new(db, "t", [bad]), "/admin", allow) end)
    assert(failed != none)
  end
end

fun test_the_pages_list_search_sort_and_page()
  let client = make(true, true)
  client.get("/admin").expect_body_contains("Posts")
  let list = client.get("/admin/posts")
  list.expect_status(200)
  list.expect_body_contains("6 row(s)")
  list.expect_body_contains("Page 1 of 2")
  list.expect_body_contains("Post 1")
  assert(not list.body.contains("Post 5"))
  client.get("/admin/posts?page=2").expect_body_contains("Post 5")
  let found = client.get("/admin/posts?q=Body 3")
  found.expect_body_contains("1 row(s)")
  found.expect_body_contains("Post 3")
  -- the column to sort by is one of ours: anything else is ignored, never put in the query
  client.get("/admin/posts?sort=title;DROP TABLE posts&dir=desc").expect_status(200)
  client.get("/admin/posts?sort=rating&dir=desc").expect_status(200)
  let sorted = client.get("/admin/posts?sort=rating&dir=desc")
  assert(sorted.body.index_of("Post 5") != none)
  client.get("/admin/posts").expect_body_contains("6 row(s)")
end

fun test_what_comes_from_the_database_is_escaped()
  let client = make(true, true)
  let list = client.get("/admin/posts?page=2")
  list.expect_body_contains("&lt;script&gt;alert(1)&lt;/script&gt;")
  assert(not list.body.contains("<script>alert(1)"))
  let q = client.get("/admin/posts?q=%22%3E%3Cimg%20src%3Dx%3E")
  assert(not q.body.contains("<img src=x>"))
end

fun test_the_json_list_and_one_row()
  let client = make(true, true)
  let list = Json.parse(client.get("/admin/api/posts").body).unwrap()
  assert_eq(jget(list, "total").as_number(), 6.0)
  assert_eq(jget(list, "per_page").as_number(), 4.0)
  assert_eq(jget(list, "pages").as_number(), 2.0)
  assert_eq(jget(list, "data").as_array().len(), 4)
  let one = Json.parse(client.get("/admin/api/posts/2").body).unwrap()
  assert_eq(jget(one, "title").as_string(), "Post 2")
  -- the columns that are not declared are not shown
  assert(one.get("secret") == none)
  client.get("/admin/api/posts/999").expect_status(404)
  client.get("/admin/api/posts/abc").expect_status(404)
  client.get("/admin/api/nothing").expect_status(404)
end

fun test_the_api_writes_with_a_csrf_token_and_only_declared_columns()
  let client = make(true, true)
  client.post_json("/admin/api/posts", {"title": "New"}).expect_status(403)
  let token = api_token(client)
  client.header("x-csrf-token", token)
  let made = client.post_json("/admin/api/posts", {"title": "New", "body": "Text", "id": "99", "secret": "x", "unknown": "y"})
  made.expect_status(201)
  let row = Json.parse(made.body).unwrap()
  assert_eq(jget(row, "title").as_string(), "New")
  assert(jget(row, "id").as_number() != 99.0)
  assert(row.get("secret") == none)
  client.post_json("/admin/api/posts", {"body": "no title"}).expect_status(422)
  client.post_json("/admin/api/posts", {"title": "  "}).expect_status(422)
  client.post_json("/admin/api/posts", {"title": "T", "rating": "not a number"}).expect_status(422)
  let id = jget(row, "id").as_number() as int
  let changed = client.put_json("/admin/api/posts/{id}", {"body": "Changed", "published": "true"})
  changed.expect_status(200)
  let after = Json.parse(changed.body).unwrap()
  assert_eq(jget(after, "body").as_string(), "Changed")
  assert_eq(jget(after, "title").as_string(), "New")
  assert_eq(jget(after, "published").as_number(), 1.0)
  client.delete("/admin/api/posts/{id}").expect_status(204)
  client.get("/admin/api/posts/{id}").expect_status(404)
  client.put_json("/admin/api/posts/{id}", {"title": "ghost"}).expect_status(404)
end

fun test_the_html_forms_create_change_and_delete()
  let client = make(true, true)
  let form = client.get("/admin/posts/new")
  form.expect_status(200)
  form.expect_body_contains("name=\"title\"")
  let start = assert_some(form.body.index_of("name=\"_csrf\" value=\"")) + 20
  let rest = form.body.substring(start, form.body.len())
  let token = rest.substring(0, rest.index_of("\"") ?? 0)
  assert(token != "")
  client.post_form("/admin/posts", {"title": "From the form"}).expect_status(403)
  client.post_form("/admin/posts", {"_csrf": token, "title": ""}).expect_status(422)
  let bad = client.post_form("/admin/posts", {"_csrf": token, "title": ""})
  bad.expect_body_contains("title is required")
  let ok = client.post_form("/admin/posts", {"_csrf": token, "title": "From the form", "body": "B", "published": "1"})
  assert(ok.status == 302 or ok.status == 303)
  client.get("/admin/posts?q=From the form").expect_body_contains("1 row(s)")
  let edit = client.get("/admin/posts/1/edit")
  edit.expect_status(200)
  edit.expect_body_contains("value=\"Post 1\"")
  client.post_form("/admin/posts/1", {"_csrf": token, "title": "Renamed"}).status
  client.get("/admin/posts?q=Renamed").expect_body_contains("1 row(s)")
  client.post_form("/admin/posts/1/delete", {}).expect_status(403)
  client.post_form("/admin/posts/1/delete", {"_csrf": token})
  client.get("/admin/api/posts/1").expect_status(404)
end

fun test_resources_can_forbid_what_they_do_not_allow()
  let client = make(true, true)
  let token = api_token(client)
  client.header("x-csrf-token", token)
  client.get("/admin/readonly").expect_status(200)
  client.get("/admin/readonly/new").expect_status(403)
  client.get("/admin/readonly/1/edit").expect_status(403)
  client.post_json("/admin/api/readonly", {"title": "x"}).expect_status(403)
  client.put_json("/admin/api/readonly/1", {"title": "x"}).expect_status(403)
  client.delete("/admin/api/readonly/1").expect_status(403)
end

fun test_the_csrf_check_can_be_turned_off_for_a_bearer_guard()
  let client = make(true, false)
  client.post_json("/admin/api/posts", {"title": "No token needed"}).expect_status(201)
end

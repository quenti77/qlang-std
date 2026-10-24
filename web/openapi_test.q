import "app.q" as web
import "openapi.q" as oa
import "test_blog.q" as blog
import "test_blog_controllers.q" as controllers

fun build() -> web.App
  let app = web.App.new(Reflect.callables(blog))
  app.controllers(Reflect.callables(controllers))
  app.controller(controllers.Shelf { label: "books" })
  app
end

fun at(j: Json, key: string) -> Json
  j.get(key) ?? Json.null()
end

fun test_the_document_lists_paths_and_methods()
  let doc = oa.openapi(build(), "Blog", "1.0.0")
  assert_eq(at(doc, "openapi").as_string(), "3.1.0")
  let paths = at(doc, "paths")
  assert(paths.get("/posts") != none)
  assert(paths.get("/posts/\{id\}") != none)
  assert(paths.get("/shelf/\{id\}") != none)
  assert(at(paths, "/posts").get("post") != none)
end

fun test_parameters_and_bodies_come_from_the_annotations()
  let text = oa.openapi(build(), "Blog", "1.0.0").to_text()
  assert(text.contains("\"in\":\"path\""))
  assert(text.contains("\"in\":\"query\""))
  assert(text.contains("\"requestBody\""))
  assert(text.contains("\"#/components/schemas/NewPost\""))
  assert(text.contains("\"in\":\"header\""))
  assert(text.contains("\"201\""))
end

fun test_schemas_carry_the_fields_and_their_validation()
  let doc = oa.openapi(build(), "Blog", "1.0.0")
  let schemas = at(at(doc, "components"), "schemas")
  let post = at(schemas, "Post").to_text()
  assert(post.contains("\"title\""))
  let new_post = at(schemas, "NewPost").to_text()
  assert(new_post.contains("minLength"))
end

fun test_a_route_can_serve_its_own_document()
  let app = build()
  oa.openapi_route(app, "/openapi.json", "Blog", "1.0.0")
  let r = app.handle(Request { method: "GET", url: "/openapi.json", path: "/openapi.json" })
  assert_eq(r.status, 200)
  assert(r.body.contains("\"openapi\":\"3.1.0\""))
end

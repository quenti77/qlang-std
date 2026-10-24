import "app.q" as web
import Posts, Post, NewPost, Clock, Me from "test_blog.q"

#[web.Get("/posts")]
fun list(posts: Posts, #[web.Query] limit: int?) -> array<Post>
  let all = posts.all()
  if limit == none then all else all.take(limit) end
end

#[web.Get("/posts/:id")]
fun show(#[web.Path] id: int, posts: Posts) -> Post?
  posts.find(id)
end

#[web.Post("/posts")]
#[web.Status(201)]
fun create(#[web.Body] input: NewPost, posts: Posts) -> Post
  posts.add(input.title)
end

#[web.Get("/me")]
fun me(who: Me) -> string
  "hello {who.name}"
end

#[web.Get("/header")]
fun with_header(#[web.Header("X-Token")] token: string, #[web.CookieValue("sid")] sid: string?) -> string
  "{token}/{sid}"
end

#[web.Get("/fail/http")]
fun fail_http() -> Result<string, HttpError>
  Result<string, HttpError>.Err(HttpError { status: 418, message: "teapot" })
end

#[web.Get("/fail/plain")]
fun fail_plain() -> Result<string, Error>
  Result<string, Error>.Err(Error { message: "secret detail" })
end

#[web.Get("/nothing")]
fun nothing()
  print("")
end

#[web.Get("/raw")]
fun raw(req: Request) -> Response
  Response.text("raw {req.path}")
end

#[web.Route("/any", method: "OPTIONS")]
fun options() -> string
  "options"
end

--" A controller written as a struct. --"
#[web.Controller("/shelf")]
struct Shelf
  public label: string
end

impl Shelf
  #[web.Get("/")]
  public fun all(self, posts: Posts) -> string
    "{self.label}: {posts.all().len()}"
  end

  #[web.Get("/:id")]
  public fun one(self, #[web.Path] id: int, posts: Posts) -> Post?
    posts.find(id)
  end

  #[web.Post("/")]
  #[web.Status(201)]
  public fun add(self, #[web.Body] input: NewPost, posts: Posts) -> Post
    posts.add(input.title)
  end

  fun not_a_route(self) -> int
    1
  end
end
export Shelf

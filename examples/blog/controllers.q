-- The routes: functions whose parameters say where their values come from.
import "../../web/app.q" as web
import "../../web/validate.q" as v
import Posts, Post from "providers.q"

struct NewPost
  #[v.NotBlank, v.Length(3, 80)]
  public title: string
  #[v.NotBlank]
  public body: string
end

struct Health
  public status: string
end

#[web.Get("/health")]
fun health() -> Health
  Health { status: "ok" }
end

#[web.Get("/posts")]
fun list(posts: Posts, #[web.Query] limit: int?) -> array<Post>
  posts.all(if limit == none then 20 else limit end)
end

#[web.Get("/posts/:id")]
fun show(#[web.Path] id: int, posts: Posts) -> Post?
  posts.find(id)
end

#[web.Post("/posts")]
#[web.Status(201)]
fun create(#[web.Body] input: NewPost, #[web.Header("X-User")] user: string, posts: Posts) -> Post
  posts.add(input.title, input.body, user)
end

#[web.Delete("/posts/:id")]
#[web.Status(204)]
fun remove(#[web.Path] id: int, posts: Posts) -> Result<string, HttpError>
  if posts.remove(id) then
    Result<string, HttpError>.Ok("")
  else
    Result<string, HttpError>.Err(HttpError { status: 404, message: "no such post" })
  end
end

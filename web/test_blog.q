-- A small application for the tests of `app.q`: services, then handlers.
import NotBlank, Length, Min, Email from "validate.q"
import Scoped from "container.q"

struct Post
  public id: int
  public title: string
end

struct NewPost
  #[NotBlank, Length(3, 40)]
  public title: string
  #[Min(0)]
  public stars: int = 0
end

struct Posts
  public items: array<Post>
end

struct Clock
  public now: int
end

struct Me
  public name: string
end

impl Posts
  public fun all(self) -> array<Post>
    self.items
  end

  public fun find(self, id: int) -> Post?
    self.items.find(fun(p: Post) -> bool p.id == id end)
  end

  public fun add(self, title: string) -> Post
    let p = Post { id: self.items.len() + 1, title: title }
    self.items.push(p)
    p
  end
end

fun make_posts() -> Posts
  Posts { items: [Post { id: 1, title: "First" }, Post { id: 2, title: "Second" }] }
end

fun make_clock() -> Clock
  Clock { now: 1000 }
end

#[Scoped]
fun make_me(req: Request) -> Me
  let who = req.header("x-user")
  Me { name: if who == none then "guest" else who end }
end

export Post, NewPost, Posts, Clock, Me

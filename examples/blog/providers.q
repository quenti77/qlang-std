-- The services of the application: each function gives the type it returns.
import "../../web/query.q" as q
import "../../web/migrate.q" as migrate
import "../../web/container.q" as di

struct Config
  public database: string
  public secret: string
end

struct Posts
  public db: Db
end

struct Post
  public id: int
  public title: string
  public body: string
  public author: string
end

impl Posts
  public fun all(self, limit: int) -> array<Post>
    q.Query.table("posts").order_by("id", "desc").limit(limit).all_as<Post>(self.db).unwrap()
  end

  public fun find(self, id: int) -> Post?
    q.Query.table("posts").where("id", "=", id).first_as<Post>(self.db).unwrap()
  end

  public fun add(self, title: string, body: string, author: string) -> Post
    q.Query.table("posts").insert(self.db, { "title": Json.string(title), "body": Json.string(body), "author": Json.string(author) }).unwrap()
    let rows = self.db.query("SELECT id FROM posts ORDER BY id DESC LIMIT 1", []).unwrap()
    let id = rows[0].get("id", Json.null()).as_number() as int
    Post { id: id, title: title, body: body, author: author }
  end

  public fun remove(self, id: int) -> bool
    q.Query.table("posts").where("id", "=", id).delete(self.db).unwrap() > 0
  end
end

fun make_config() -> Config
  let database = env.get("BLOG_DB")
  let secret = env.get("BLOG_SECRET")
  Config { database: if database == none then "sqlite://:memory:" else database end, secret: if secret == none then "dev-only-secret" else secret end }
end

fun make_db(config: Config) -> Db
  let db = Db.connect(config.database).unwrap()
  let applied = migrate.Migrator.new(db).run([
    migrate.Migration {
      id: "001_posts",
      up: [
        "CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL, author TEXT NOT NULL)",
        "INSERT INTO posts (title, body, author) VALUES ('Hello', 'The first post', 'ada')",
      ],
      down: ["DROP TABLE posts"],
    },
  ]).unwrap()
  Log.info("database ready, {applied.len()} migration(s) applied")
  db
end

fun make_posts(db: Db) -> Posts
  Posts { db: db }
end

export Config, Posts, Post

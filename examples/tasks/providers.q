-- The services of the application: each function gives the type it returns.
import "../../web/query.q" as q
import "../../web/migrate.q" as migrate
import "../../web/container.q" as di

struct Config
  public database: string
  public secret: string
end

struct User
  public id: int
  public email: string
end

--" A user as the database holds it, with the hash of the password (never sent out). --"
struct UserRow
  public id: int
  public email: string
  public password_hash: string
end

struct Task
  public id: int
  public title: string
  public done: bool
end

--" A task as the table holds it: SQLite keeps a boolean as 0 or 1. --"
struct TaskRow
  public id: int
  public title: string
  public done: int
end

impl TaskRow
  public fun to_task(self) -> Task
    Task { id: self.id, title: self.title, done: self.done != 0 }
  end
end

struct Users
  public db: Db
end

struct Tasks
  public db: Db
end

--" Who is making the request: filled in by the `auth` guard. --"
struct Me
  public id: int
  public email: string
end

impl Users
  public fun register(self, email: string, password: string) -> Result<User, Error>
    let hash = Password.hash(password)
    if hash.is_err() then
      return Result<User, Error>.Err(hash.unwrap_err())
    end
    let saved = q.Query.table("users").insert(self.db, { "email": Json.string(email), "password_hash": Json.string(hash.unwrap()) })
    if saved.is_err() then
      return Result<User, Error>.Err(saved.unwrap_err())
    end
    let found = self.by_email(email)
    if found == none then
      return Result<User, Error>.Err(Error { message: "the user was not saved" })
    end
    Result<User, Error>.Ok(User { id: found.id, email: found.email })
  end

  public fun by_email(self, email: string) -> UserRow?
    q.Query.table("users").where("email", "=", email).first_as<UserRow>(self.db).unwrap()
  end

  public fun by_id(self, id: int) -> UserRow?
    q.Query.table("users").where("id", "=", id).first_as<UserRow>(self.db).unwrap()
  end
end

impl Tasks
  public fun for_user(self, user: int, done: bool?) -> array<Task>
    let query = q.Query.table("tasks").where("user_id", "=", user)
    if done != none then
      query = query.where("done", "=", if done then 1 else 0 end)
    end
    query.order_by("id", "asc").all_as<TaskRow>(self.db).unwrap().map(fun(r: TaskRow) -> Task r.to_task() end)
  end

  public fun find(self, user: int, id: int) -> Task?
    let row = q.Query.table("tasks").where("user_id", "=", user).where("id", "=", id).first_as<TaskRow>(self.db).unwrap()
    if row == none then none else row.to_task() end
  end

  public fun add(self, user: int, title: string) -> Task
    q.Query.table("tasks").insert(self.db, { "user_id": Json.number(user as float), "title": Json.string(title), "done": Json.number(0.0) }).unwrap()
    let rows = self.db.query("SELECT id FROM tasks ORDER BY id DESC LIMIT 1", []).unwrap()
    let id = rows[0].get("id", Json.null()).as_number() as int
    Task { id: id, title: title, done: false }
  end

  public fun finish(self, user: int, id: int) -> Task?
    q.Query.table("tasks").where("user_id", "=", user).where("id", "=", id).update(self.db, { "done": Json.number(1.0) }).unwrap()
    self.find(user, id)
  end

  public fun remove(self, user: int, id: int) -> bool
    q.Query.table("tasks").where("user_id", "=", user).where("id", "=", id).delete(self.db).unwrap() > 0
  end
end

fun make_config() -> Config
  Config { database: env.get("TASKS_DB") ?? "sqlite://:memory:", secret: env.get("TASKS_SECRET") ?? "dev-only-secret" }
end

fun make_db(config: Config) -> Db
  let db = Db.connect(config.database).unwrap()
  migrate.Migrator.new(db).run([
    migrate.Migration {
      id: "001_users",
      up: ["CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL)"],
      down: ["DROP TABLE users"],
    },
    migrate.Migration {
      id: "002_tasks",
      up: ["CREATE TABLE tasks (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, title TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0)"],
      down: ["DROP TABLE tasks"],
    },
  ]).unwrap()
  db
end

fun make_users(db: Db) -> Users
  Users { db: db }
end

fun make_tasks(db: Db) -> Tasks
  Tasks { db: db }
end

--" Built for each request from what the guard learned. --"
#[di.Scoped]
fun make_me(req: Request) -> Me
  let held = req.attrs["me"]
  let me = if held == none then none else held.as<Me>() end
  me ?? Me { id: 0, email: "" }
end

export Config, User, UserRow, Task, Users, Tasks, Me

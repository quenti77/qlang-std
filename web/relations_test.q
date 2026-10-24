import "relations.q" as rel
import "query.q" as q

struct User
  public id: int
  public name: string
end

struct Post
  public id: int
  public user_id: int
  public title: string
end

struct Role
  public id: int
  public label: string
end

struct Profile
  public user_id: int
  public bio: string
end

fun database() -> Db
  let db = Db.connect("sqlite://:memory:").unwrap()
  db.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)", [])
  db.execute("CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT)", [])
  db.execute("CREATE TABLE roles (id INTEGER PRIMARY KEY, label TEXT)", [])
  db.execute("CREATE TABLE role_user (user_id INTEGER, role_id INTEGER)", [])
  db.execute("CREATE TABLE profiles (user_id INTEGER, bio TEXT)", [])
  db.execute("INSERT INTO users (id, name) VALUES (1, 'Ada'), (2, 'Bob'), (3, 'Cyd')", [])
  db.execute("INSERT INTO posts (id, user_id, title) VALUES (1, 1, 'A1'), (2, 1, 'A2'), (3, 2, 'B1')", [])
  db.execute("INSERT INTO roles (id, label) VALUES (1, 'admin'), (2, 'editor')", [])
  db.execute("INSERT INTO role_user (user_id, role_id) VALUES (1, 1), (1, 2), (2, 2)", [])
  db.execute("INSERT INTO profiles (user_id, bio) VALUES (1, 'maths')", [])
  db
end

fun users(db: Db) -> array<User>
  q.Query.table("users").order_by("id", "asc").all_as<User>(db).unwrap()
end

fun test_has_many_gives_each_parent_its_children_in_one_query_each()
  let db = database()
  let loaded = rel.has_many<User, Post>(db, users(db), "id", "posts", "user_id").unwrap()
  assert_eq(loaded.len(), 3)
  assert_eq(loaded[0].item.name, "Ada")
  assert_eq(loaded[0].related.map(fun(p: Post) -> string p.title end), ["A1", "A2"])
  assert_eq(loaded[1].related.len(), 1)
  assert_eq(loaded[2].related.len(), 0)
end

fun test_has_many_where_can_filter_and_order_the_children()
  let db = database()
  let newest_first = fun(query: q.Query) -> q.Query query.order_by("id", "desc") end
  let loaded = rel.has_many_where<User, Post>(db, users(db), "id", "posts", "user_id", newest_first).unwrap()
  assert_eq(loaded[0].related.map(fun(p: Post) -> string p.title end), ["A2", "A1"])
end

fun test_has_one_and_belongs_to()
  let db = database()
  let profiles = rel.has_one<User, Profile>(db, users(db), "id", "profiles", "user_id").unwrap()
  assert_eq((profiles[0].related ?? Profile { user_id: 0, bio: "?" }).bio, "maths")
  assert(profiles[1].related == none)
  let posts = q.Query.table("posts").order_by("id", "asc").all_as<Post>(db).unwrap()
  let owners = rel.belongs_to<Post, User>(db, posts, "user_id", "users", "id").unwrap()
  assert_eq(owners.map(fun(w: rel.With<Post, User?>) -> string (w.related ?? User { id: 0, name: "?" }).name end), ["Ada", "Ada", "Bob"])
end

fun test_belongs_to_many_goes_through_the_pivot_table()
  let db = database()
  let loaded = rel.belongs_to_many<User, Role>(db, users(db), "id", "role_user", "user_id", "role_id", "roles", "id").unwrap()
  assert_eq(loaded[0].related.map(fun(r: Role) -> string r.label end), ["admin", "editor"])
  assert_eq(loaded[1].related.map(fun(r: Role) -> string r.label end), ["editor"])
  assert_eq(loaded[2].related.len(), 0)
end

fun test_no_parent_means_no_query_and_a_bad_table_name_is_an_error()
  let db = database()
  let none_at_all: array<User> = []
  assert_eq(rel.has_many<User, Post>(db, none_at_all, "id", "posts", "user_id").unwrap().len(), 0)
  assert(rel.has_many<User, Post>(db, users(db), "id", "posts; DROP TABLE users", "user_id").is_err())
end

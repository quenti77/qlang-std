import "seed.q" as seed
import "query.q" as q

fun text(row: map<string, Json>, column: string) -> string
  let v = row[column]
  if v == none then "(none)" else v.as_string() end
end

fun users_factory() -> seed.Factory
  let f = seed.Factory.table("users")
  f.field("name", fun(n: int) -> Json Json.string("User {n}") end)
  f.field("email", fun(n: int) -> Json Json.string("user{n}@example.com") end)
  f.field("role", fun(n: int) -> Json Json.string("member") end)
  f.state("admin", {"role": Json.string("admin")})
  f
end

fun database() -> Db
  let db = Db.connect("sqlite://:memory:").unwrap()
  db.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE, role TEXT NOT NULL)", []).unwrap()
  db
end

fun count(db: Db) -> int
  q.Query.table("users").count(db).unwrap()
end

fun test_make_numbers_the_rows_and_does_not_save()
  let f = users_factory()
  let first = f.make()
  let second = f.make()
  assert_eq(text(first, "name"), "User 1")
  assert_eq(text(second, "email"), "user2@example.com")
  assert_eq(f.make_many(3).len(), 3)
end

fun test_overrides_and_states_replace_the_values()
  let f = users_factory()
  let ada = f.make_with({"name": Json.string("Ada")})
  assert_eq(text(ada, "name"), "Ada")
  assert_eq(text(ada, "role"), "member")
  let admin = f.make_state("admin", {"name": Json.string("Root")})
  assert_eq(text(admin, "role"), "admin")
  assert_eq(text(admin, "name"), "Root")
end

fun test_create_inserts_and_gives_the_row()
  let db = database()
  let f = users_factory()
  let made = f.create(db).unwrap()
  assert_eq(text(made, "email"), "user1@example.com")
  assert_eq(count(db), 1)
  let found = q.Query.table("users").where("email", "=", "user1@example.com").first(db).unwrap()
  assert(found != none)
  f.create_state(db, "admin", {}).unwrap()
  assert_eq(q.Query.table("users").where("role", "=", "admin").count(db).unwrap(), 1)
end

fun test_create_many_gives_every_row_in_order()
  let db = database()
  let rows = users_factory().create_many(db, 5).unwrap()
  assert_eq(rows.len(), 5)
  assert_eq(count(db), 5)
  assert_eq(text(rows[4], "name"), "User 5")
end

fun test_a_failing_insert_is_an_error_not_a_panic()
  let db = database()
  let f = users_factory()
  f.field("email", fun(n: int) -> Json Json.string("same@example.com") end)
  assert(f.create_many(db, 2).is_err())
  -- all or none: the first row was undone with the second
  assert_eq(count(db), 0)
end

fun test_seeders_run_in_order_each_in_a_transaction()
  let db = database()
  let f = users_factory()
  let seeders = [
    seed.Seeder { name: "first", run: fun(d: Db) -> Result<bool, Error>
      seed.done(f.create_many(d, 2))
    end },
    seed.Seeder { name: "second", run: fun(d: Db) -> Result<bool, Error>
      seed.done(f.create(d))
    end },
  ]
  let ran = seed.run_seeders(db, seeders).unwrap()
  assert_eq(ran.join(","), "first,second")
  assert_eq(count(db), 3)
end

fun test_a_failing_seeder_is_undone_and_stops_the_rest()
  let db = database()
  let f = users_factory()
  let broken = users_factory()
  broken.field("email", fun(n: int) -> Json Json.string("dup@example.com") end)
  let seeders = [
    seed.Seeder { name: "ok", run: fun(d: Db) -> Result<bool, Error>
      seed.done(f.create(d))
    end },
    seed.Seeder { name: "broken", run: fun(d: Db) -> Result<bool, Error>
      seed.done(broken.create_many(d, 2))
    end },
    seed.Seeder { name: "never", run: fun(d: Db) -> Result<bool, Error>
      seed.done(f.create(d))
    end },
  ]
  let outcome = seed.run_seeders(db, seeders)
  assert(outcome.is_err())
  assert(outcome.unwrap_err().message.starts_with("seeder broken:"))
  -- "ok" stayed, "broken" was undone, "never" did not run
  assert_eq(count(db), 1)
end

import "migrate.q" as m

fun migrations() -> array<m.Migration>
  [
    m.Migration { id: "002_age", up: ["ALTER TABLE users ADD COLUMN age INTEGER"], down: [] },
    m.Migration { id: "001_users", up: ["CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)", "INSERT INTO users (name) VALUES ('first')"], down: ["DROP TABLE users"] },
  ]
end

fun count_rows(db: Db) -> int
  db.query("SELECT COUNT(*) AS n FROM users", []).unwrap()[0].get("n", Json.null()).as_number() as int
end

fun test_pending_migrations_run_in_order_of_their_ids()
  let db = Db.connect("sqlite://:memory:").unwrap()
  let migrator = m.Migrator.new(db)
  let applied = migrator.run(migrations()).unwrap()
  assert_eq(applied, ["001_users", "002_age"])
  assert_eq(count_rows(db), 1)
  db.execute("INSERT INTO users (name, age) VALUES ('x', 3)", []).unwrap()
end

fun test_an_applied_migration_is_not_run_again()
  let db = Db.connect("sqlite://:memory:").unwrap()
  let migrator = m.Migrator.new(db)
  migrator.run(migrations()).unwrap()
  assert_eq(migrator.run(migrations()).unwrap(), [])
  assert_eq(count_rows(db), 1)
  let status = migrator.status(migrations()).unwrap()
  assert_eq(status.len(), 2)
  assert(status[0].applied and status[1].applied)
end

fun test_rollback_undoes_the_newest_first()
  let db = Db.connect("sqlite://:memory:").unwrap()
  let migrator = m.Migrator.new(db)
  migrator.run(migrations()).unwrap()
  assert_eq(migrator.rollback(migrations(), 1).unwrap(), ["002_age"])
  let status = migrator.status(migrations()).unwrap()
  assert(status[0].applied)
  assert(not status[1].applied)
  assert_eq(migrator.rollback(migrations(), 5).unwrap(), ["001_users"])
  assert(db.query("SELECT * FROM users", []).is_err())
  -- and forward again
  assert_eq(migrator.run(migrations()).unwrap(), ["001_users", "002_age"])
end

fun test_a_failing_migration_leaves_the_database_as_it_was()
  let db = Db.connect("sqlite://:memory:").unwrap()
  let migrator = m.Migrator.new(db)
  let bad = [
    m.Migration { id: "001_ok", up: ["CREATE TABLE users (id INTEGER PRIMARY KEY)"] },
    m.Migration { id: "002_bad", up: ["CREATE TABLE posts (id INTEGER PRIMARY KEY)", "NOT SQL AT ALL"] },
  ]
  let r = migrator.run(bad)
  assert(r.is_err())
  assert(r.unwrap_err().message.starts_with("migration 002_bad:"))
  assert(db.query("SELECT * FROM users", []).is_ok())
  assert(db.query("SELECT * FROM posts", []).is_err())
  let status = migrator.status(bad).unwrap()
  assert(status[0].applied)
  assert(not status[1].applied)
end

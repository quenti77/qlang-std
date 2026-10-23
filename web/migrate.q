--" # Migrations

A migration is a numbered change of the database schema: SQL to go forward (`up`) and SQL to go
back (`down`). The migrator remembers which ones were applied in a table (`schema_migrations`) and
applies the others, in order.

```
let migrations = [
  Migration { id: "001_users", up: ["CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)"], down: ["DROP TABLE users"] },
  Migration { id: "002_age", up: ["ALTER TABLE users ADD COLUMN age INTEGER"], down: [] },
]
let m = Migrator.new(db)
m.run(migrations)           -- Result<array<string>, Error>: the ids it applied
m.rollback(migrations, 1)   -- undoes the last one
```

Each migration runs in a transaction: if one of its statements fails, the database is left as it
was and the error says which migration it was. (MySQL commits a schema change by itself: a failed
migration there may have been applied in part.) Write migrations so that running them twice is not
needed: an id that was applied is never run again.
--"

--" One schema change: a unique `id` (sorted, so start it with a number or a date), the statements to
apply and the statements to undo it. --"
struct Migration
  public id: string
  public up: array<string>
  public down: array<string> = []
end

--" Applies and undoes migrations on a database. --"
struct Migrator
  public db: Db
  public table: string
end

--" Where a migration stands. --"
struct MigrationStatus
  public id: string
  public applied: bool
end

fun migrate_error<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
end

impl Migrator
  --" A migrator that remembers in the table `schema_migrations`. --"
  public fun new(db: Db) -> Migrator
    Migrator { db: db, table: "schema_migrations" }
  end

  fun prepare(self) -> Result<bool, Error>
    let r = self.db.execute("CREATE TABLE IF NOT EXISTS {self.table} (id VARCHAR(190) PRIMARY KEY, applied_at VARCHAR(40) NOT NULL)", [])
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  fun applied_ids(self) -> Result<array<string>, Error>
    let rows = self.db.query("SELECT id FROM {self.table} ORDER BY id", [])
    if rows.is_err() then
      return Result<array<string>, Error>.Err(rows.unwrap_err())
    end
    let out: array<string> = []
    for row in rows.unwrap() do
      let id = row["id"]
      if id != none then
        out.push(id.as_string())
      end
    end
    Result<array<string>, Error>.Ok(out)
  end

  --" Which migrations are applied. --"
  public fun status(self, migrations: array<Migration>) -> Result<array<MigrationStatus>, Error>
    let ready = self.prepare()
    if ready.is_err() then
      return Result<array<MigrationStatus>, Error>.Err(ready.unwrap_err())
    end
    let done = self.applied_ids()
    if done.is_err() then
      return Result<array<MigrationStatus>, Error>.Err(done.unwrap_err())
    end
    let known = done.unwrap()
    let out: array<MigrationStatus> = []
    for m in sorted(migrations) do
      out.push(MigrationStatus { id: m.id, applied: known.contains(m.id) })
    end
    Result<array<MigrationStatus>, Error>.Ok(out)
  end

  --" Applies the migrations that were not yet, in the order of their ids. Gives the ids it applied.
  It stops at the first failure. --"
  public fun run(self, migrations: array<Migration>) -> Result<array<string>, Error>
    let ready = self.prepare()
    if ready.is_err() then
      return Result<array<string>, Error>.Err(ready.unwrap_err())
    end
    let done = self.applied_ids()
    if done.is_err() then
      return Result<array<string>, Error>.Err(done.unwrap_err())
    end
    let known = done.unwrap()
    let applied: array<string> = []
    for m in sorted(migrations) do
      if known.contains(m.id) then
        continue
      end
      let r = self.apply(m, m.up, true)
      if r.is_err() then
        return Result<array<string>, Error>.Err(r.unwrap_err())
      end
      applied.push(m.id)
    end
    Result<array<string>, Error>.Ok(applied)
  end

  --" Undoes the last `steps` applied migrations, newest first. Gives the ids it undid. A migration
  without `down` statements is undone by forgetting it only. --"
  public fun rollback(self, migrations: array<Migration>, steps: int) -> Result<array<string>, Error>
    let ready = self.prepare()
    if ready.is_err() then
      return Result<array<string>, Error>.Err(ready.unwrap_err())
    end
    let done = self.applied_ids()
    if done.is_err() then
      return Result<array<string>, Error>.Err(done.unwrap_err())
    end
    let known = done.unwrap()
    let ordered = sorted(migrations)
    ordered.reverse()
    let undone: array<string> = []
    for m in ordered do
      if undone.len() >= steps then
        break
      end
      if not known.contains(m.id) then
        continue
      end
      let r = self.apply(m, m.down, false)
      if r.is_err() then
        return Result<array<string>, Error>.Err(r.unwrap_err())
      end
      undone.push(m.id)
    end
    Result<array<string>, Error>.Ok(undone)
  end

  fun apply(self, m: Migration, statements: array<string>, forward: bool) -> Result<bool, Error>
    let begun = self.db.begin()
    if begun.is_err() then
      return Result<bool, Error>.Err(begun.unwrap_err())
    end
    for sql in statements do
      let r = self.db.execute(sql, [])
      if r.is_err() then
        self.db.rollback()
        return migrate_error<bool>("migration {m.id}: {r.unwrap_err().message}")
      end
    end
    let mark = if forward then
      self.db.execute("INSERT INTO {self.table} (id, applied_at) VALUES (?, ?)", [Json.string(m.id), Json.string(datetime.now().format("YYYY-MM-DD HH:mm:ss"))])
    else
      self.db.execute("DELETE FROM {self.table} WHERE id = ?", [Json.string(m.id)])
    end
    if mark.is_err() then
      self.db.rollback()
      return migrate_error<bool>("migration {m.id}: {mark.unwrap_err().message}")
    end
    let ended = self.db.commit()
    if ended.is_err() then
      self.db.rollback()
      return Result<bool, Error>.Err(ended.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end
end

fun sorted(migrations: array<Migration>) -> array<Migration>
  let copy = migrations.concat([])
  copy.sort_by(fun(a: Migration, b: Migration) -> int
    if a.id < b.id then
      return -1
    end
    if a.id > b.id then 1 else 0 end
  end)
  copy
end

export Migration, Migrator, MigrationStatus

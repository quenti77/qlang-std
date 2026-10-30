--" # Test data: factories and seeders

A **factory** builds rows of a table with values that change from one row to the next, so that a test
(or a development database) is filled in one line instead of ten `INSERT`s.

```
let users = Factory.table("users")
users.field("name", fun(n: int) -> Json Json.string("User {n}") end)
users.field("email", fun(n: int) -> Json Json.string("user{n}@example.com") end)
users.field("role", fun(n: int) -> Json Json.string("member") end)
users.state("admin", {"role": Json.string("admin")})

users.make()                                   -- {"name": "User 1", ...}, not saved
users.create(db)                               -- inserted: Result<map<string, Json>, Error>, the row
users.create_with(db, {"name": Json.string("Ada")})            -- one value changed
users.create_state(db, "admin", {})            -- a named variation
users.create_many(db, 25)                      -- 25 rows: Result<array<map<string, Json>>, Error>
```

`field` takes a function of the **number of the row** (1, 2, 3...): it makes the unique emails and the
names. A `state` is a set of values that replaces the ones of the fields (an admin, a deleted post...).

A **seeder** is a named function that fills a database; `run_seeders` runs them in order, each in a
transaction, and stops at the first one that fails, saying which. `qlang run console.q -- db:seed`
(`commands.q`) runs the ones you registered.

```
let seeders = [
  Seeder { name: "users", run: fun(db: Db) -> Result<bool, Error>
    done(users.create_many(db, 10))
  end },
]
run_seeders(db, seeders)                       -- Result<array<string>, Error>: the names it ran
```
--"
import "query.q" as q

--" Builds rows of one table. --"
struct Factory
  table: string
  columns: array<string>
  makers: map<string, fun(int) -> Json>
  states: map<string, map<string, Json>>
  made: int
end

fun insert_row(table: string, db: Db, row: map<string, Json>) -> Result<map<string, Json>, Error>
  let done = q.Query.table(table).insert(db, row)
  if done.is_err() then
    return Result<map<string, Json>, Error>.Err(done.unwrap_err())
  end
  Result<map<string, Json>, Error>.Ok(row)
end

impl Factory
  --" A factory for this table. --"
  public fun table(name: string) -> Factory
    Factory { table: name, columns: [], makers: {}, states: {}, made: 0 }
  end

  --" How to make the value of a column: `maker` receives the number of the row (1, 2, 3...). Giving
  the same column again replaces it. --"
  public fun field(self, column: string, maker: fun(int) -> Json) -> Factory
    if self.makers[column] == none then
      self.columns.push(column)
    end
    self.makers[column] = maker
    self
  end

  --" A named variation: these values replace the ones of the fields. --"
  public fun state(self, name: string, values: map<string, Json>) -> Factory
    self.states[name] = values
    self
  end

  --" The next row, not saved. `overrides` replace the values of the fields. --"
  public fun make_with(self, overrides: map<string, Json>) -> map<string, Json>
    self.made += 1
    let row: map<string, Json> = {}
    for column in self.columns do
      let maker = self.makers[column]
      if maker != none then
        row[column] = maker(self.made)
      end
    end
    for column in overrides.keys() do
      row[column] = overrides[column] ?? Json.null()
    end
    row
  end

  --" The next row, not saved. --"
  public fun make(self) -> map<string, Json>
    self.make_with({})
  end

  --" The next row with a state applied (an unknown state is a panic: it is a typo in a test). --"
  public fun make_state(self, state: string, overrides: map<string, Json>) -> map<string, Json>
    let changes = self.states[state]
    if changes == none then
      panic("the factory of {self.table} has no state called {state}")
    end
    let merged: map<string, Json> = {}
    for column in changes.keys() do
      merged[column] = changes[column] ?? Json.null()
    end
    for column in overrides.keys() do
      merged[column] = overrides[column] ?? Json.null()
    end
    self.make_with(merged)
  end

  --" `n` rows, not saved. --"
  public fun make_many(self, n: int) -> array<map<string, Json>>
    let rows: array<map<string, Json>> = []
    for i in 0..n do
      rows.push(self.make())
    end
    rows
  end

  --" Makes a row and inserts it. It gives the row that was inserted, with the values it was made of
  (a column the database fills itself, like an automatic `id`, is not in it: give the factory a
  `field("id", ...)` to choose it, or read the table). --"
  public fun create_with(self, db: Db, overrides: map<string, Json>) -> Result<map<string, Json>, Error>
    insert_row(self.table, db, self.make_with(overrides))
  end

  --" Makes a row and inserts it: the row. --"
  public fun create(self, db: Db) -> Result<map<string, Json>, Error>
    self.create_with(db, {})
  end

  --" Makes a row with a state and inserts it: the row. --"
  public fun create_state(self, db: Db, state: string, overrides: map<string, Json>) -> Result<map<string, Json>, Error>
    insert_row(self.table, db, self.make_state(state, overrides))
  end

  --" Inserts `n` rows and gives them, in order. It stops at the first error; wrap the call in a
  transaction (`db.begin()`) when all or none is wanted: `run_seeders` does it for each seeder. --"
  public fun create_many(self, db: Db, n: int) -> Result<array<map<string, Json>>, Error>
    let rows: array<map<string, Json>> = []
    for i in 0..n do
      let made = self.create(db)
      if made.is_err() then
        return Result<array<map<string, Json>>, Error>.Err(made.unwrap_err())
      end
      rows.push(made.unwrap())
    end
    Result<array<map<string, Json>>, Error>.Ok(rows)
  end
end

--" A named function that fills a database. --"
struct Seeder
  public name: string
  public run: fun(Db) -> Result<bool, Error>
end

--" A seeder's way to say it worked: `done(users.create_many(db, 10))` is `Ok(true)`, or the error of
the call it wraps. --"
fun done<T>(result: Result<T, Error>) -> Result<bool, Error>
  if result.is_err() then
    return Result<bool, Error>.Err(result.unwrap_err())
  end
  Result<bool, Error>.Ok(true)
end

--" Runs the seeders in order, each in a transaction (a failure undoes that one and stops
there). The names of the ones that ran, or the error with the name of the one that failed. --"
fun run_seeders(db: Db, seeders: array<Seeder>) -> Result<array<string>, Error>
  let ran: array<string> = []
  for s in seeders do
    let started = db.begin()
    if started.is_err() then
      return Result<array<string>, Error>.Err(started.unwrap_err())
    end
    let outcome = s.run(db)
    if outcome.is_err() then
      db.rollback()
      return Result<array<string>, Error>.Err(Error { message: "seeder {s.name}: {outcome.unwrap_err().message}" })
    end
    let done = db.commit()
    if done.is_err() then
      return Result<array<string>, Error>.Err(done.unwrap_err())
    end
    ran.push(s.name)
  end
  Result<array<string>, Error>.Ok(ran)
end

export Factory, Seeder, run_seeders, done

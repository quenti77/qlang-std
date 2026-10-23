--" # Query builder

Builds the SQL of a query step by step, with `?` placeholders for the values (so a value is never
part of the SQL text), and runs it on a `Db`. Table and column names are checked (letters, digits,
`_`, one `.` for `table.column`): anything else is an error, never SQL.

```
let users = Query.table("users")
users.where("age", ">=", 18)
users.where_in("role", ["admin", "member"])
users.order_by("name", "asc")
users.limit(20)
let rows = users.all(db)                  -- Result<array<map<string, Json>>, Error>
let people = users.all_as<Person>(db)     -- Result<array<Person>, Error>
```

Every method that adds something to the query returns the query itself, so calls can be chained
on one line: `Query.table("users").where("id", "=", 3).first(db)`.
--"

--" A SELECT, INSERT, UPDATE or DELETE under construction. --"
struct Query
  name: string
  fields: array<string>
  conditions: array<string>
  values: array<Json>
  orders: array<string>
  max: int
  skip: int
  problem: string?
end

fun valid_name(name: string) -> bool
  name == "*" or regex.matches(name, "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)?(\\.\\*)?$")
end

fun query_error<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
end

impl Query
  --" A query on this table. --"
  public fun table(name: string) -> Query
    let q = Query { name: name, fields: [], conditions: [], values: [], orders: [], max: -1, skip: 0, problem: none }
    if not valid_name(name) or name == "*" then
      q.problem = "`{name}` is not a table name"
    end
    q
  end

  fun reject(self, message: string)
    if self.problem == none then
      self.problem = message
    end
  end

  fun column(self, name: string) -> string
    if not valid_name(name) then
      self.reject("`{name}` is not a column name")
    end
    name
  end

  --" The columns to read (all of them by default). --"
  public fun select(self, columns: array<string>) -> Query
    for c in columns do
      self.fields.push(self.column(c))
    end
    self
  end

  --" Keeps the rows where `column op value`; `op` is `=`, `!=`, `<`, `<=`, `>`, `>=`, `LIKE` or
  `NOT LIKE`. Several calls are joined with AND. --"
  public fun where<T>(self, column: string, op: string, value: T) -> Query
    let o = op.upper()
    if not ["=", "!=", "<>", "<", "<=", ">", ">=", "LIKE", "NOT LIKE"].contains(o) then
      self.reject("`{op}` is not a comparison")
    end
    self.conditions.push("{self.column(column)} {o} ?")
    self.values.push(Json.of(value))
    self
  end

  --" Keeps the rows whose `column` is one of these values. --"
  public fun where_in<T>(self, column: string, options: array<T>) -> Query
    if options.is_empty() then
      self.conditions.push("1 = 0")
      return self
    end
    let marks = options.map(fun(o: T) -> string "?" end)
    self.conditions.push("{self.column(column)} IN ({marks.join(", ")})")
    for o in options do
      self.values.push(Json.of(o))
    end
    self
  end

  --" Keeps the rows whose `column` is `NULL` (`is_null`) or is not (`not_null`). --"
  public fun is_null(self, column: string) -> Query
    self.conditions.push("{self.column(column)} IS NULL")
    self
  end

  public fun not_null(self, column: string) -> Query
    self.conditions.push("{self.column(column)} IS NOT NULL")
    self
  end

  --" Sorts by a column, `"asc"` or `"desc"`. --"
  public fun order_by(self, column: string, direction: string) -> Query
    let d = direction.upper()
    if d != "ASC" and d != "DESC" then
      self.reject("`{direction}` is not asc or desc")
    end
    self.orders.push("{self.column(column)} {d}")
    self
  end

  --" At most `n` rows. --"
  public fun limit(self, n: int) -> Query
    if n < 0 then
      self.reject("a limit cannot be negative")
    end
    self.max = n
    self
  end

  --" Skips the first `n` rows (with `limit`). --"
  public fun offset(self, n: int) -> Query
    if n < 0 then
      self.reject("an offset cannot be negative")
    end
    self.skip = n
    self
  end

  fun where_sql(self) -> string
    if self.conditions.is_empty() then
      ""
    else
      " WHERE " + self.conditions.join(" AND ")
    end
  end

  --" The SQL of the SELECT. --"
  public fun to_sql(self) -> string
    let cols = if self.fields.is_empty() then "*" else self.fields.join(", ") end
    let sql = "SELECT {cols} FROM {self.name}" + self.where_sql()
    if not self.orders.is_empty() then
      sql += " ORDER BY " + self.orders.join(", ")
    end
    if self.max >= 0 then
      sql += " LIMIT {self.max}"
      if self.skip > 0 then
        sql += " OFFSET {self.skip}"
      end
    end
    sql
  end

  --" The values that go with the `?` of the SQL, in order. --"
  public fun params(self) -> array<Json>
    self.values
  end

  --" The rows, each as a map from column to value. --"
  public fun all(self, db: Db) -> Result<array<map<string, Json>>, Error>
    let bad = self.problem
    if bad != none then
      return query_error<array<map<string, Json>>>(bad)
    end
    db.query(self.to_sql(), self.values)
  end

  --" The first row, or `none`. --"
  public fun first(self, db: Db) -> Result<map<string, Json>?, Error>
    let one = Query { name: self.name, fields: self.fields, conditions: self.conditions, values: self.values, orders: self.orders, max: 1, skip: self.skip, problem: self.problem }
    let rows = one.all(db)
    if rows.is_err() then
      return Result<map<string, Json>?, Error>.Err(rows.unwrap_err())
    end
    let list = rows.unwrap()
    let found: map<string, Json>? = list.first()
    Result<map<string, Json>?, Error>.Ok(found)
  end

  --" How many rows match. --"
  public fun count(self, db: Db) -> Result<int, Error>
    let bad = self.problem
    if bad != none then
      return query_error<int>(bad)
    end
    let rows = db.query("SELECT COUNT(*) AS n FROM {self.name}" + self.where_sql(), self.values)
    if rows.is_err() then
      return Result<int, Error>.Err(rows.unwrap_err())
    end
    let first = rows.unwrap().first()
    if first == none then
      return Result<int, Error>.Ok(0)
    end
    let n = first["n"]
    if n == none then
      return Result<int, Error>.Ok(0)
    end
    Result<int, Error>.Ok(n.as_number() as int)
  end

  --" The rows read as values of the type `T` (a structure with a field for each column; see
  `Json.to`). --"
  public fun all_as<T>(self, db: Db) -> Result<array<T>, Error>
    let rows = self.all(db)
    if rows.is_err() then
      return Result<array<T>, Error>.Err(rows.unwrap_err())
    end
    let out: array<T> = []
    for row in rows.unwrap() do
      let item = Json.to<T>(Json.object(row))
      if item.is_err() then
        return Result<array<T>, Error>.Err(item.unwrap_err())
      end
      out.push(item.unwrap())
    end
    Result<array<T>, Error>.Ok(out)
  end

  --" The first row read as a `T`, or `none`. --"
  public fun first_as<T>(self, db: Db) -> Result<T?, Error>
    let row = self.first(db)
    if row.is_err() then
      return Result<T?, Error>.Err(row.unwrap_err())
    end
    let found = row.unwrap()
    if found == none then
      return Result<T?, Error>.Ok(none)
    end
    let item = Json.to<T>(Json.object(found))
    if item.is_err() then
      return Result<T?, Error>.Err(item.unwrap_err())
    end
    Result<T?, Error>.Ok(item.unwrap())
  end

  --" Inserts a row: its columns and values. Gives the number of rows inserted. --"
  public fun insert(self, db: Db, row: map<string, Json>) -> Result<int, Error>
    let bad = self.problem
    if bad != none then
      return query_error<int>(bad)
    end
    if row.is_empty() then
      return query_error<int>("nothing to insert")
    end
    let names = row.keys()
    let marks: array<string> = []
    let params: array<Json> = []
    for n in names do
      if not valid_name(n) or n == "*" then
        return query_error<int>("`{n}` is not a column name")
      end
      marks.push("?")
      let v = row[n]
      params.push(if v == none then Json.null() else v end)
    end
    db.execute("INSERT INTO {self.name} ({names.join(", ")}) VALUES ({marks.join(", ")})", params)
  end

  --" Inserts a structure: a column for each public field. --"
  public fun insert_value<T>(self, db: Db, value: T) -> Result<int, Error>
    let j = Json.of(value)
    if not j.is_object() then
      return query_error<int>("only a structure can be inserted")
    end
    self.insert(db, j.as_object())
  end

  --" Changes the columns of the rows that match. Gives the number of rows changed. --"
  public fun update(self, db: Db, changes: map<string, Json>) -> Result<int, Error>
    let bad = self.problem
    if bad != none then
      return query_error<int>(bad)
    end
    if changes.is_empty() then
      return query_error<int>("nothing to change")
    end
    if self.conditions.is_empty() then
      return query_error<int>("an update without a condition would change every row: add a where")
    end
    let sets: array<string> = []
    let params: array<Json> = []
    for n in changes.keys() do
      if not valid_name(n) or n == "*" then
        return query_error<int>("`{n}` is not a column name")
      end
      sets.push("{n} = ?")
      let v = changes[n]
      params.push(if v == none then Json.null() else v end)
    end
    for v in self.values do
      params.push(v)
    end
    db.execute("UPDATE {self.name} SET {sets.join(", ")}" + self.where_sql(), params)
  end

  --" Deletes the rows that match. Gives the number of rows deleted. --"
  public fun delete(self, db: Db) -> Result<int, Error>
    let bad = self.problem
    if bad != none then
      return query_error<int>(bad)
    end
    if self.conditions.is_empty() then
      return query_error<int>("a delete without a condition would remove every row: add a where")
    end
    db.execute("DELETE FROM {self.name}" + self.where_sql(), self.values)
  end
end

export Query

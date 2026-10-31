--" # Relations

Loads the rows that belong to a list of rows **with one query** (not one per row, the "N+1" of
lazy ORMs). Each function takes the parents you already have and gives them back, each with what
relates to it:

```
struct User
  public id: int
  public name: string
end

struct Post
  public id: int
  public user_id: int
  public title: string
end

let users = Query.table("users").all_as<User>(db).unwrap()
let loaded = has_many<User, Post>(db, users, "id", "posts", "user_id").unwrap()
for u in loaded do
  print("{u.item.name}: {u.related.len()} post(s)")
end
```

| Function | Relation | `related` is |
| --- | --- | --- |
| `has_many<P, C>(db, parents, key, table, foreign_key)` | a user has many posts | `array<C>` |
| `has_one<P, C>(...)` | a user has one profile | `C?` |
| `belongs_to<C, O>(db, children, foreign_key, table, key)` | a post belongs to a user | `O?` |
| `belongs_to_many<P, R>(db, parents, key, pivot, parent_key, related_key, table, id)` | a user has many roles, through a table | `array<R>` |

Columns and tables are checked like in `Query`; values are `?` parameters. The fields are read through
`Json.of`, so a `#[JsonName("e_mail")]` on a field is the name of its column. Add `.where(...)` to
the rows you load with `constrain`: a function that gets the query before it runs.
--"

import "query.q" as q

--" A row and what relates to it. --"
struct With<P, R>
  public item: P
  public related: R
end

-- The values of the field `name` of each item (without duplicates), as Json, and the Json of each item.
fun keys_of<P>(items: array<P>, name: string) -> Result<array<Json>, Error>
  let seen: map<string, bool> = {}
  let out: array<Json> = []
  for item in items do
    let value = Json.of(item).get(name)
    if value == none or value.is_null() then
      continue
    end
    let id = value.to_text()
    if seen[id] == none then
      seen[id] = true
      out.push(value)
    end
  end
  Result<array<Json>, Error>.Ok(out)
end

fun key_text<P>(item: P, name: string) -> string?
  let value = Json.of(item).get(name)
  if value == none or value.is_null() then
    return none
  end
  value.to_text()
end

-- The rows of `table` whose `column` is one of `ids`, grouped by the value of that column.
fun rows_by(db: Db, table: string, column: string, ids: array<Json>, constrain: fun(q.Query) -> q.Query) -> Result<map<string, array<map<string, Json>>>, Error>
  let groups: map<string, array<map<string, Json>>> = {}
  if ids.is_empty() then
    return Result<map<string, array<map<string, Json>>>, Error>.Ok(groups)
  end
  let query = constrain(q.Query.table(table).where_in(column, ids))
  let rows = query.all(db)
  if rows.is_err() then
    return Result<map<string, array<map<string, Json>>>, Error>.Err(rows.unwrap_err())
  end
  for row in rows.unwrap() do
    let id = (row[column] ?? Json.null()).to_text()
    let list = groups[id]
    if list == none then
      groups[id] = [row]
    else
      list.push(row)
    end
  end
  Result<map<string, array<map<string, Json>>>, Error>.Ok(groups)
end

fun same(query: q.Query) -> q.Query
  query
end

--" The `C` rows whose `foreign_key` is the `key` of each parent. --"
fun has_many<P, C>(db: Db, parents: array<P>, key: string, table: string, foreign_key: string) -> Result<array<With<P, array<C>>>, Error>
  has_many_where<P, C>(db, parents, key, table, foreign_key, same)
end

--" `has_many` with a function that adds conditions or an order to the query of the children. --"
fun has_many_where<P, C>(db: Db, parents: array<P>, key: string, table: string, foreign_key: string, constrain: fun(q.Query) -> q.Query) -> Result<array<With<P, array<C>>>, Error>
  let ids = keys_of<P>(parents, key)
  if ids.is_err() then
    return Result<array<With<P, array<C>>>, Error>.Err(ids.unwrap_err())
  end
  let groups = rows_by(db, table, foreign_key, ids.unwrap(), constrain)
  if groups.is_err() then
    return Result<array<With<P, array<C>>>, Error>.Err(groups.unwrap_err())
  end
  let out: array<With<P, array<C>>> = []
  for parent in parents do
    let children: array<C> = []
    let id = key_text<P>(parent, key)
    if id != none then
      for row in groups.unwrap()[id] ?? [] do
        let child = Json.to<C>(Json.object(row))
        if child.is_err() then
          return Result<array<With<P, array<C>>>, Error>.Err(child.unwrap_err())
        end
        children.push(child.unwrap())
      end
    end
    out.push(With<P, array<C>> { item: parent, related: children })
  end
  Result<array<With<P, array<C>>>, Error>.Ok(out)
end

--" The first `C` row whose `foreign_key` is the `key` of each parent. --"
fun has_one<P, C>(db: Db, parents: array<P>, key: string, table: string, foreign_key: string) -> Result<array<With<P, C?>>, Error>
  let many = has_many<P, C>(db, parents, key, table, foreign_key)
  if many.is_err() then
    return Result<array<With<P, C?>>, Error>.Err(many.unwrap_err())
  end
  let out: array<With<P, C?>> = []
  for w in many.unwrap() do
    out.push(With<P, C?> { item: w.item, related: if w.related.is_empty() then none else w.related[0] end })
  end
  Result<array<With<P, C?>>, Error>.Ok(out)
end

--" The `O` row each child points to: the one whose `key` is the child's `foreign_key`. --"
fun belongs_to<C, O>(db: Db, children: array<C>, foreign_key: string, table: string, key: string) -> Result<array<With<C, O?>>, Error>
  let ids = keys_of<C>(children, foreign_key)
  if ids.is_err() then
    return Result<array<With<C, O?>>, Error>.Err(ids.unwrap_err())
  end
  let groups = rows_by(db, table, key, ids.unwrap(), same)
  if groups.is_err() then
    return Result<array<With<C, O?>>, Error>.Err(groups.unwrap_err())
  end
  let out: array<With<C, O?>> = []
  for child in children do
    let owner: O? = none
    let id = key_text<C>(child, foreign_key)
    if id != none then
      let rows = groups.unwrap()[id] ?? []
      if not rows.is_empty() then
        let read = Json.to<O>(Json.object(rows[0]))
        if read.is_err() then
          return Result<array<With<C, O?>>, Error>.Err(read.unwrap_err())
        end
        owner = read.unwrap()
      end
    end
    out.push(With<C, O?> { item: child, related: owner })
  end
  Result<array<With<C, O?>>, Error>.Ok(out)
end

--" Many-to-many through a table: `pivot` has a `parent_key` column (the `key` of the parent) and a
`related_key` column (the `id` of the related row in `table`). --"
fun belongs_to_many<P, R>(db: Db, parents: array<P>, key: string, pivot: string, parent_key: string, related_key: string, table: string, id: string) -> Result<array<With<P, array<R>>>, Error>
  let ids = keys_of<P>(parents, key)
  if ids.is_err() then
    return Result<array<With<P, array<R>>>, Error>.Err(ids.unwrap_err())
  end
  let links = rows_by(db, pivot, parent_key, ids.unwrap(), same)
  if links.is_err() then
    return Result<array<With<P, array<R>>>, Error>.Err(links.unwrap_err())
  end
  -- the related ids, once each
  let wanted: array<Json> = []
  let seen: map<string, bool> = {}
  for parent_id in links.unwrap().keys() do
    for link in links.unwrap()[parent_id] ?? [] do
      let r = link[related_key] ?? Json.null()
      if not r.is_null() and seen[r.to_text()] == none then
        seen[r.to_text()] = true
        wanted.push(r)
      end
    end
  end
  let related = rows_by(db, table, id, wanted, same)
  if related.is_err() then
    return Result<array<With<P, array<R>>>, Error>.Err(related.unwrap_err())
  end
  let out: array<With<P, array<R>>> = []
  for parent in parents do
    let list: array<R> = []
    let pid = key_text<P>(parent, key)
    if pid != none then
      for link in links.unwrap()[pid] ?? [] do
        let r = link[related_key] ?? Json.null()
        for row in related.unwrap()[r.to_text()] ?? [] do
          let read = Json.to<R>(Json.object(row))
          if read.is_err() then
            return Result<array<With<P, array<R>>>, Error>.Err(read.unwrap_err())
          end
          list.push(read.unwrap())
        end
      end
    end
    out.push(With<P, array<R>> { item: parent, related: list })
  end
  Result<array<With<P, array<R>>>, Error>.Ok(out)
end

export With, has_many, has_many_where, has_one, belongs_to, belongs_to_many

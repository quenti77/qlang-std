import "query.q" as q

struct Person
  public id: int
  public name: string
  public age: int
  public email: string?
end

fun database() -> Db
  let db = Db.connect("sqlite://:memory:").unwrap()
  db.execute("CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER, email TEXT)", [])
  db.execute("INSERT INTO people (name, age, email) VALUES ('Ada', 36, 'ada@x.org'), ('Bob', 17, NULL), ('Cyd', 52, NULL)", [])
  db
end

fun test_the_sql_is_built_with_placeholders_for_every_value()
  let query = q.Query.table("people")
  query.select(["id", "name"])
  query.where("age", ">=", 18)
  query.where("name", "LIKE", "A%")
  query.order_by("name", "desc")
  query.limit(10)
  query.offset(5)
  assert_eq(query.to_sql(), "SELECT id, name FROM people WHERE age >= ? AND name LIKE ? ORDER BY name DESC LIMIT 10 OFFSET 5")
  assert_eq(query.params().len(), 2)
end

fun test_rows_come_back_as_maps_and_as_structures()
  let db = database()
  let adults = q.Query.table("people").where("age", ">=", 18).order_by("age", "asc")
  let rows = adults.all(db).unwrap()
  assert_eq(rows.len(), 2)
  assert_eq(rows[0].get("name", Json.null()).as_string(), "Ada")
  let people = adults.all_as<Person>(db).unwrap()
  assert_eq(people[1].name, "Cyd")
  assert_eq(people[0].email, "ada@x.org")
  assert_eq(people[1].email, none)
end

fun test_first_count_and_in()
  let db = database()
  assert_eq(q.Query.table("people").count(db).unwrap(), 3)
  assert_eq(q.Query.table("people").where("age", ">", 40).count(db).unwrap(), 1)
  let first = q.Query.table("people").where_in("name", ["Bob", "Cyd"]).order_by("name", "asc").first(db).unwrap()
  assert(first != none)
  assert(q.Query.table("people").where("age", ">", 100).first(db).unwrap() == none)
  let one = q.Query.table("people").where("name", "=", "Bob").first_as<Person>(db).unwrap()
  assert(one != none)
  assert_eq(q.Query.table("people").where_in("name", ["nobody"]).count(db).unwrap(), 0)
  assert_eq(q.Query.table("people").is_null("email").count(db).unwrap(), 2)
  assert_eq(q.Query.table("people").not_null("email").count(db).unwrap(), 1)
end

fun test_insert_update_and_delete()
  let db = database()
  let added = q.Query.table("people").insert(db, { "name": Json.string("Dee"), "age": Json.number(29.0) })
  assert_eq(added.unwrap(), 1)
  assert_eq(q.Query.table("people").count(db).unwrap(), 4)
  let changed = q.Query.table("people").where("name", "=", "Dee").update(db, { "age": Json.number(30.0) })
  assert_eq(changed.unwrap(), 1)
  assert_eq(q.Query.table("people").where("age", "=", 30).count(db).unwrap(), 1)
  let removed = q.Query.table("people").where("age", "<", 18).delete(db)
  assert_eq(removed.unwrap(), 1)
  assert_eq(q.Query.table("people").count(db).unwrap(), 3)
end

fun test_a_structure_can_be_inserted()
  let db = database()
  let p = Person { id: 10, name: "Eve", age: 41, email: none }
  assert_eq(q.Query.table("people").insert_value(db, p).unwrap(), 1)
  let back = q.Query.table("people").where("id", "=", 10).first_as<Person>(db).unwrap()
  if back == none then
    panic("the row was not found")
  end
  assert_eq(back.name, "Eve")
end

fun test_names_and_operators_are_checked_so_sql_cannot_be_injected()
  let db = database()
  assert(q.Query.table("people; DROP TABLE people").all(db).is_err())
  assert(q.Query.table("people").where("age) OR (1=1", "=", 1).all(db).is_err())
  assert(q.Query.table("people").where("age", "= 1 OR 1 =", 1).all(db).is_err())
  assert(q.Query.table("people").order_by("age", "asc; DROP").all(db).is_err())
  assert(q.Query.table("people").limit(-1).all(db).is_err())
  assert_eq(q.Query.table("people").count(db).unwrap(), 3)
  -- a value is never SQL
  let tricky = q.Query.table("people").where("name", "=", "x' OR '1'='1").count(db)
  assert_eq(tricky.unwrap(), 0)
end

fun test_update_and_delete_need_a_condition()
  let db = database()
  assert(q.Query.table("people").update(db, { "age": Json.number(1.0) }).is_err())
  assert(q.Query.table("people").delete(db).is_err())
  assert_eq(q.Query.table("people").count(db).unwrap(), 3)
end

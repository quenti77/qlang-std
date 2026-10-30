import "resource.q" as r
import "query.q" as q

struct Account
  public id: int
  public name: string
  public password_hash: string
end

fun at(j: Json, name: string) -> Json
  j.get(name) ?? Json.null()
end

fun row() -> map<string, Json>
  {"id": Json.number(7.0), "name": Json.string("Ada"), "password_hash": Json.string("x"), "created": Json.string("2026")}
end

fun test_only_shows_the_listed_fields_in_order()
  let shown = r.Resource.only(["name", "id", "missing"]).one(row())
  assert_eq(shown.to_text(), "\{\"name\":\"Ada\",\"id\":7}")
end

fun test_hide_shows_the_rest_renamed_and_computed()
  let shown = r.Resource.hide(["password_hash"]).rename("created", "created_at").add("label", fun(row: map<string, Json>) -> Json
    Json.string("#" + (row["name"] ?? Json.null()).as_string())
  end).one(row())
  assert(at(shown, "password_hash").is_null())
  assert_eq(at(shown, "created_at").as_string(), "2026")
  assert_eq(at(shown, "label").as_string(), "#Ada")
  assert_eq(at(shown, "name").as_string(), "Ada")
end

fun test_a_structure_and_a_list_can_be_shown()
  let view = r.Resource.only(["id", "name"])
  let one = view.of_value(Account { id: 1, name: "Bob", password_hash: "secret" })
  assert_eq(one.to_text(), "\{\"id\":1,\"name\":\"Bob\"}")
  assert_eq(view.many([row(), row()]).as_array().len(), 2)
end

fun test_a_page_goes_through_a_resource()
  let db = Db.connect("sqlite://:memory:").unwrap()
  db.execute("CREATE TABLE u (id INTEGER PRIMARY KEY, name TEXT, secret TEXT)", [])
  db.execute("INSERT INTO u (name, secret) VALUES ('a', 's'), ('b', 's')", [])
  let page = q.Query.table("u").order_by("id", "asc").paginate(db, 1, 10).unwrap()
  let body = page.to_json_with("", r.Resource.only(["name"]).shape())
  assert_eq(at(body, "data").to_text(), "[\{\"name\":\"a\"},\{\"name\":\"b\"}]")
end

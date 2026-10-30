--" # Resources: what an API shows of a model

A **resource** decides which fields of a row (or of a structure) an API shows, under which names, and
adds computed ones. The same model can have several: a short one for a list, a full one for the
page of one item, one for the owner and one for the others. A field that is not listed is never sent,
so a `password_hash` cannot leak by accident.

```
let short = Resource.only(["id", "title"])
let full = Resource.hide(["password_hash", "deleted_at"])
  .rename("created", "created_at")
  .add("url", fun(row: map<string, Json>) -> Json Json.string("/posts/{row["id"]}") end)

short.one(row)                      -- Json: {"id": 1, "title": "..."}
full.many(rows)                     -- Json: an array
full.of_value(post)                 -- a structure (`Json.of`) instead of a row
page.to_json_with("/posts", short.shape())   -- a page of the query builder, rows through the resource
```
--"

--" How to show a row. --"
type Shaper = fun(map<string, Json>) -> Json

struct Resource
  fields: array<string>
  hidden: array<string>
  all: bool
  renames: map<string, string>
  added: array<string>
  makers: map<string, fun(map<string, Json>) -> Json>
end

impl Resource
  --" Shows only these fields, in this order (a name the row does not have is left out). --"
  public fun only(fields: array<string>) -> Resource
    Resource { fields: fields, hidden: [], all: false, renames: {}, added: [], makers: {} }
  end

  --" Shows every field except these. --"
  public fun hide(hidden: array<string>) -> Resource
    Resource { fields: [], hidden: hidden, all: true, renames: {}, added: [], makers: {} }
  end

  --" Shows the field `field` under the name `name`. --"
  public fun rename(self, field: string, name: string) -> Resource
    self.renames[field] = name
    self
  end

  --" Adds a computed field: `make` receives the whole row (including the fields that are hidden). --"
  public fun add(self, name: string, make: fun(map<string, Json>) -> Json) -> Resource
    if self.makers[name] == none then
      self.added.push(name)
    end
    self.makers[name] = make
    self
  end

  fun named(self, field: string) -> string
    self.renames[field] ?? field
  end

  --" One row shown: a JSON object. --"
  public fun one(self, row: map<string, Json>) -> Json
    let out: map<string, Json> = {}
    if self.all then
      for field in row.keys() do
        if not self.hidden.contains(field) then
          out[self.named(field)] = row[field] ?? Json.null()
        end
      end
    else
      for field in self.fields do
        let value = row[field]
        if value != none then
          out[self.named(field)] = value
        end
      end
    end
    for name in self.added do
      let make = self.makers[name]
      if make != none then
        out[name] = make(row)
      end
    end
    Json.object(out)
  end

  --" Many rows shown: a JSON array. --"
  public fun many(self, rows: array<map<string, Json>>) -> Json
    let out: array<Json> = []
    for row in rows do
      out.push(self.one(row))
    end
    Json.array(out)
  end

  --" A structure shown (its fields as `Json.of` writes them, so `#[JsonSkip]` still applies). --"
  public fun of_value<T>(self, value: T) -> Json
    self.one(Json.of(value).as_object())
  end

  --" The resource as a function, for `Page.to_json_with`. --"
  public fun shape(self) -> Shaper
    let resource = self
    let shaper = fun(row: map<string, Json>) -> Json
      resource.one(row)
    end
    shaper
  end
end

export Resource, Shaper

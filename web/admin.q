--" # Administration panel

A panel to look at, search, create, change and delete the rows of your tables: a JSON API for your own
front end, and plain HTML pages (no JavaScript, nothing to install) for a quick back office.

```
let admin = Admin.new(db, "Back office", [
  Resource {
    name: "users", table: "accounts", title: "Users",
    columns: [
      Column { name: "email", searchable: true, required: true },
      Column { name: "verified_at", label: "Verified", kind: "number", editable: false },
    ],
  },
  Resource {
    name: "posts", table: "posts", title: "Posts", per_page: 25,
    columns: [
      Column { name: "title", searchable: true, required: true },
      Column { name: "body", kind: "textarea" },
      Column { name: "published", kind: "bool" },
    ],
  },
])

app.use(sessions(secret))                       -- the panel needs the sessions (for its forms' CSRF token)
mount(app, admin, "/admin", require_verified(accounts))
```

**You must give a guard**: `mount` has no way to be called without one, so a panel is never left open by
forgetting it. Give it the guard of your choice (`require_login(accounts)` of `accounts.q`, a check of a role of
yours...). Whoever passes it can read and change every table you listed: list only what an administrator may touch,
and leave out the secrets (a `password_hash` column has no business here).

| Page | What |
| --- | --- |
| `GET /admin` | the list of the resources |
| `GET /admin/users` | a table: `?q=` searches the searchable columns, `?sort=email&dir=desc`, `?page=2` |
| `GET /admin/users/new`, `POST /admin/users` | the form and the creation |
| `GET /admin/users/7/edit`, `POST /admin/users/7` | the form and the change |
| `POST /admin/users/7/delete` | the deletion |
| `GET /admin/api/users` | the same list as JSON: `{"data": [...], "page", "per_page", "total", "pages"}` |
| `GET /admin/api/users/7`, `POST /admin/api/users`, `PUT /admin/api/users/7`, `DELETE /admin/api/users/7` | one row, create, change, delete |

What it takes care of: every text put in a page is escaped; the column to sort by and the columns to write are
checked against the ones you declared (a request cannot name another); the values go to the database as bound
parameters; every `POST`, `PUT` and `DELETE` needs the CSRF token of the session (the field `_csrf` of the forms, the
header `X-CSRF-Token` for the API, given by `GET /admin/api/csrf`) unless you turn it off with `csrf: false` (when the
guard is a bearer token, which a browser does not send by itself).

What it does not do: roles or per-row rights (the guard is all or nothing), an audit log, relations between tables
(a foreign key is a number), files, or forms that are not made of text, numbers, booleans and long texts. For
those, write your own page: this one is the quick way, not the last one.

Booleans are stored as the integers `0` and `1`, which every database takes (a `BOOLEAN` column of PostgreSQL
does not take an integer: use a `SMALLINT`).
--"
import "app.q" as web
import "session.q" as sess

--" A column of a table. `kind` is `text`, `textarea`, `number` or `bool`. --"
struct Column
  public name: string
  --" The title in the table (the name by default). --"
  public label: string = ""
  public kind: string = "text"
  --" Can the form change it? --"
  public editable: bool = true
  --" Does `?q=` look in it? --"
  public searchable: bool = false
  --" The form refuses an empty value. --"
  public required: bool = false
end

--" A table of the panel. The key column (`id`) is shown and never changed. --"
struct Resource
  --" The name in the addresses (`users`): letters, digits, `_` and `-`; not `api`. --"
  public name: string
  public table: string
  public title: string
  public columns: array<Column>
  public key: string = "id"
  public per_page: int = 20
  public can_create: bool = true
  public can_edit: bool = true
  public can_delete: bool = true
end

--" The panel: a database and the resources it shows. --"
struct Admin
  public db: Db
  public title: string
  public resources: array<Resource>
  --" Ask for the CSRF token on `POST`, `PUT` and `DELETE`. --"
  public csrf: bool = true
end

impl Admin
  public fun new(db: Db, title: string, resources: array<Resource>) -> Admin
    Admin { db: db, title: title, resources: resources }
  end

  public fun find(self, name: string) -> Resource?
    for r in self.resources do
      if r.name == name then
        return r
      end
    end
    none
  end
end

-- ------------------------------------------------------------------------ small helpers

fun esc(text: string) -> string
  text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")
end

fun number(n: int) -> Json
  Json.number(n as float)
end

fun label_of(c: Column) -> string
  if c.label == "" then c.name else c.label end
end

fun valid_name(name: string) -> bool
  if name == "" or name == "api" then
    return false
  end
  for c in name.chars() do
    if not (c.is_alpha() or c.is_digit() or c == "_" or c == "-") then
      return false
    end
  end
  true
end

fun valid_identifier(name: string) -> bool
  if name == "" then
    return false
  end
  for c in name.chars() do
    if not (c.is_alpha() or c.is_digit() or c == "_") then
      return false
    end
  end
  true
end

-- a mistake in the configuration is found when mounting, not on the first request
fun check_resource(r: Resource) -> string?
  if not valid_name(r.name) then
    return "the resource name \"{r.name}\" must be letters, digits, `_` or `-`, and not `api`"
  end
  if not valid_identifier(r.table) or not valid_identifier(r.key) then
    return "{r.name}: the table and the key must be plain names"
  end
  if r.per_page < 1 or r.per_page > 100 then
    return "{r.name}: per_page is from 1 to 100"
  end
  for c in r.columns do
    if not valid_identifier(c.name) then
      return "{r.name}: the column \"{c.name}\" must be a plain name"
    end
    if not ["text", "textarea", "number", "bool"].contains(c.kind) then
      return "{r.name}: the column {c.name} has an unknown kind \"{c.kind}\""
    end
  end
  none
end

fun column_names(r: Resource) -> array<string>
  let names: array<string> = [r.key]
  for c in r.columns do
    names.push(c.name)
  end
  names
end

fun problem(status: int, message: string) -> Response
  web.Problem { status: status, message: message }.to_response()
end

fun wants_json(req: Request) -> bool
  req.path.contains("/api/")
end

-- ------------------------------------------------------------------------ the data

struct Listing
  public rows: array<map<string, Json>>
  public page: int
  public per_page: int
  public total: int
  public pages: int
end

fun search_sql(r: Resource, q: string, params: array<Json>) -> string
  if q == "" then
    return ""
  end
  let parts: array<string> = []
  for c in r.columns do
    if c.searchable then
      parts.push("{c.name} LIKE ?")
      params.push(Json.string("%" + q + "%"))
    end
  end
  if parts.is_empty() then
    return ""
  end
  " WHERE (" + parts.join(" OR ") + ")"
end

fun list_rows(admin: Admin, r: Resource, req: Request) -> Result<Listing, Error>
  let q = (req.query["q"] ?? "").trim()
  let page = int.parse(req.query["page"] ?? "1") ?? 1
  if page < 1 then
    page = 1
  end
  let per = int.parse(req.query["per_page"] ?? "{r.per_page}") ?? r.per_page
  if per < 1 or per > 100 then
    per = r.per_page
  end
  -- the column to sort by is one of ours, never the text of the request
  let sort = req.query["sort"] ?? r.key
  if not column_names(r).contains(sort) then
    sort = r.key
  end
  let dir = if (req.query["dir"] ?? "asc").lower() == "desc" then "DESC" else "ASC" end
  let params: array<Json> = []
  let where_sql = search_sql(r, q, params)
  let counted = admin.db.query("SELECT COUNT(*) AS n FROM {r.table}{where_sql}", params)
  if counted.is_err() then
    return Result<Listing, Error>.Err(counted.unwrap_err())
  end
  let total = counted.unwrap()[0].get("n", Json.null()).as_number() as int
  let pages = if total == 0 then 1 else (total + per - 1) div per end
  let rows = admin.db.query("SELECT {column_names(r).join(", ")} FROM {r.table}{where_sql} ORDER BY {sort} {dir} LIMIT {per} OFFSET {(page - 1) * per}", params)
  if rows.is_err() then
    return Result<Listing, Error>.Err(rows.unwrap_err())
  end
  Result<Listing, Error>.Ok(Listing { rows: rows.unwrap(), page: page, per_page: per, total: total, pages: pages })
end

fun find_row(admin: Admin, r: Resource, id: int) -> map<string, Json>?
  let rows = admin.db.query("SELECT {column_names(r).join(", ")} FROM {r.table} WHERE {r.key} = ?", [number(id)])
  if rows.is_err() or rows.unwrap().is_empty() then
    return none
  end
  rows.unwrap()[0]
end

struct Values
  public set: map<string, Json>
  public errors: array<string>
end

-- what the request writes, checked against the columns (an unknown field is ignored, never written)
fun values_of(r: Resource, given: map<string, string>, partial: bool) -> Values
  let set: map<string, Json> = {}
  let errors: array<string> = []
  for c in r.columns do
    if not c.editable then
      continue
    end
    let raw = given[c.name]
    if c.kind == "bool" then
      -- an unchecked box is not sent at all
      if raw != none or not partial then
        let on = raw != none and ["1", "true", "on", "yes"].contains(raw.lower())
        set[c.name] = number(if on then 1 else 0 end)
      end
      continue
    end
    if raw == none then
      if c.required and not partial then
        errors.push("{label_of(c)} is required")
      end
      continue
    end
    let text = raw
    if c.required and text.trim() == "" then
      errors.push("{label_of(c)} is required")
      continue
    end
    if c.kind == "number" then
      if text.trim() == "" then
        set[c.name] = Json.null()
      else
        let n = text.trim().to_float()
        if n == none then
          errors.push("{label_of(c)} must be a number")
        else
          set[c.name] = Json.number(n)
        end
      end
    else
      set[c.name] = Json.string(text)
    end
  end
  Values { set: set, errors: errors }
end

fun insert_row(admin: Admin, r: Resource, set: map<string, Json>) -> Result<int, Error>
  if set.is_empty() then
    return Result<int, Error>.Err(Error { message: "nothing to write" })
  end
  let names = set.keys()
  let marks: array<string> = []
  let params: array<Json> = []
  for n in names do
    marks.push("?")
    params.push(set[n] ?? Json.null())
  end
  let done = admin.db.execute("INSERT INTO {r.table} ({names.join(", ")}) VALUES ({marks.join(", ")})", params)
  if done.is_err() then
    return Result<int, Error>.Err(done.unwrap_err())
  end
  let last = admin.db.query("SELECT MAX({r.key}) AS id FROM {r.table}", [])
  if last.is_err() or last.unwrap().is_empty() then
    return Result<int, Error>.Ok(0)
  end
  Result<int, Error>.Ok(last.unwrap()[0].get("id", Json.null()).as_number() as int)
end

fun update_row(admin: Admin, r: Resource, id: int, set: map<string, Json>) -> Result<int, Error>
  if set.is_empty() then
    return Result<int, Error>.Ok(0)
  end
  let assigns: array<string> = []
  let params: array<Json> = []
  for n in set.keys() do
    assigns.push("{n} = ?")
    params.push(set[n] ?? Json.null())
  end
  params.push(number(id))
  admin.db.execute("UPDATE {r.table} SET {assigns.join(", ")} WHERE {r.key} = ?", params)
end

-- ------------------------------------------------------------------------ HTML

fun page_html(admin: Admin, title: string, body: string) -> Response
  let nav: array<string> = []
  for r in admin.resources do
    nav.push("<a href=\"@@BASE@@/{esc(r.name)}\">{esc(r.title)}</a>")
  end
  Response.html("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>{esc(title)} - {esc(admin.title)}</title><style>body\{font:15px/1.5 system-ui,sans-serif;margin:0;color:#222\}header\{background:#222;padding:.6rem 1rem\}header a\{color:#fff;margin-right:1rem;text-decoration:none\}main\{padding:1rem;max-width:70rem;margin:auto\}table\{border-collapse:collapse;width:100%\}th,td\{border-bottom:1px solid #ddd;padding:.4rem .6rem;text-align:left;vertical-align:top\}th a\{color:inherit\}input[type=text],input[type=number],textarea\{width:100%;box-sizing:border-box;padding:.4rem\}label\{display:block;margin:.8rem 0 .2rem;font-weight:600\}.error\{color:#a00\}.pager a\{margin-right:.6rem\}button,.button\{padding:.4rem .9rem;border:1px solid #222;background:#fff;cursor:pointer;text-decoration:none;color:#222\}.danger\{border-color:#a00;color:#a00\}form.inline\{display:inline\}@media(prefers-color-scheme:dark)\{body\{background:#161616;color:#ddd\}button,.button\{background:#161616;color:#ddd;border-color:#888\}th,td\{border-color:#333\}\}</style></head><body><header><strong style=\"color:#fff;margin-right:1.5rem\">{esc(admin.title)}</strong>{nav.join("")}</header><main><h1>{esc(title)}</h1>{body}</main></body></html>")
end

fun cell_text(v: Json) -> string
  if v.is_null() then
    return ""
  end
  if v.is_string() then
    return v.as_string()
  end
  v.to_text()
end

fun table_html(r: Resource, l: Listing, req: Request, token: string) -> string
  let q = (req.query["q"] ?? "").trim()
  let sort = req.query["sort"] ?? r.key
  let dir = req.query["dir"] ?? "asc"
  let out: array<string> = []
  out.push("<form method=\"get\" action=\"@@BASE@@/{esc(r.name)}\"><input type=\"text\" name=\"q\" value=\"{esc(q)}\" placeholder=\"Search\" style=\"width:20rem\"> <button type=\"submit\">Search</button>")
  if r.can_create then
    out.push(" <a class=\"button\" href=\"@@BASE@@/{esc(r.name)}/new\">New</a>")
  end
  out.push("</form><p>{l.total} row(s)</p><table><thead><tr>")
  for name in column_names(r) do
    let flip = if sort == name and dir == "asc" then "desc" else "asc" end
    let title = name
    for c in r.columns do
      if c.name == name then
        title = label_of(c)
      end
    end
    out.push("<th><a href=\"@@BASE@@/{esc(r.name)}?q={esc(Url.encode(q))}&amp;sort={esc(name)}&amp;dir={flip}\">{esc(title)}</a></th>")
  end
  out.push("<th></th></tr></thead><tbody>")
  for row in l.rows do
    out.push("<tr>")
    for name in column_names(r) do
      out.push("<td>{esc(cell_text(row.get(name, Json.null())))}</td>")
    end
    let id = cell_text(row.get(r.key, Json.null()))
    out.push("<td>")
    if r.can_edit then
      out.push("<a class=\"button\" href=\"@@BASE@@/{esc(r.name)}/{esc(id)}/edit\">Edit</a> ")
    end
    if r.can_delete then
      out.push("<form class=\"inline\" method=\"post\" action=\"@@BASE@@/{esc(r.name)}/{esc(id)}/delete\" onsubmit=\"return confirm('Delete this row?')\"><input type=\"hidden\" name=\"_csrf\" value=\"{esc(token)}\"><button class=\"danger\" type=\"submit\">Delete</button></form>")
    end
    out.push("</td></tr>")
  end
  out.push("</tbody></table><p class=\"pager\">")
  if l.page > 1 then
    out.push("<a href=\"@@BASE@@/{esc(r.name)}?q={esc(Url.encode(q))}&amp;sort={esc(sort)}&amp;dir={esc(dir)}&amp;page={l.page - 1}\">&larr; Previous</a>")
  end
  out.push("Page {l.page} of {l.pages}")
  if l.page < l.pages then
    out.push(" <a href=\"@@BASE@@/{esc(r.name)}?q={esc(Url.encode(q))}&amp;sort={esc(sort)}&amp;dir={esc(dir)}&amp;page={l.page + 1}\">Next &rarr;</a>")
  end
  out.push("</p>")
  out.join("")
end

fun form_html(r: Resource, action: string, row: map<string, Json>?, errors: array<string>, given: map<string, string>, token: string) -> string
  let out: array<string> = []
  if not errors.is_empty() then
    out.push("<ul class=\"error\">")
    for e in errors do
      out.push("<li>{esc(e)}</li>")
    end
    out.push("</ul>")
  end
  out.push("<form method=\"post\" action=\"{esc(action)}\"><input type=\"hidden\" name=\"_csrf\" value=\"{esc(token)}\">")
  for c in r.columns do
    if not c.editable then
      continue
    end
    let current = ""
    if given[c.name] != none then
      current = given[c.name] ?? ""
    elseif row != none then
      current = cell_text(row.get(c.name, Json.null()))
    end
    let id = "f_{esc(c.name)}"
    if c.kind == "bool" then
      let on = ["1", "true", "on", "yes"].contains(current.lower())
      out.push("<label for=\"{id}\"><input type=\"checkbox\" id=\"{id}\" name=\"{esc(c.name)}\" value=\"1\"{if on then " checked" else "" end}> {esc(label_of(c))}</label>")
    elseif c.kind == "textarea" then
      out.push("<label for=\"{id}\">{esc(label_of(c))}</label><textarea id=\"{id}\" name=\"{esc(c.name)}\" rows=\"6\">{esc(current)}</textarea>")
    else
      let kind = if c.kind == "number" then "number\" step=\"any" else "text" end
      out.push("<label for=\"{id}\">{esc(label_of(c))}</label><input type=\"{kind}\" id=\"{id}\" name=\"{esc(c.name)}\" value=\"{esc(current)}\"{if c.required then " required" else "" end}>")
    end
  end
  out.push("<p><button type=\"submit\">Save</button> <a class=\"button\" href=\"@@BASE@@/{esc(r.name)}\">Cancel</a></p></form>")
  out.join("")
end

-- ------------------------------------------------------------------------ routes

fun csrf_ok(admin: Admin, req: Request) -> bool
  if not admin.csrf then
    return true
  end
  let expected = sess.session_of(req).get("_csrf")
  if expected == none then
    return false
  end
  let given = req.header("x-csrf-token")
  if given == none then
    let form = req.form()
    if form.is_ok() then
      given = form.unwrap()["_csrf"]
    end
  end
  given != none and Crypto.equal(expected, given)
end

fun json_fields(req: Request) -> map<string, string>
  let out: map<string, string> = {}
  let parsed = Json.parse(req.body ?? "")
  if parsed.is_ok() and parsed.unwrap().is_object() then
    let o = parsed.unwrap().as_object()
    for k in o.keys() do
      let v = o[k] ?? Json.null()
      if v.is_string() then
        out[k] = v.as_string()
      elseif v.is_null() then
        continue
      else
        out[k] = v.to_text()
      end
    end
  end
  out
end

fun form_fields(req: Request) -> map<string, string>
  let f = req.form()
  if f.is_ok() then f.unwrap() else {} end
end

fun redirect(base: string, path: string) -> Response
  Response.redirect(base + path)
end

fun rendered(base: string, res: Response) -> Response
  res.body = res.body.replace("@@BASE@@", base)
  res
end

--" Adds the pages and the API of the table above under `prefix` (`"/admin"`), behind `guard`. The session
middleware must be on. Panics at once if a resource is badly declared. --"
fun mount(app: web.App, admin: Admin, prefix: string, guard: web.GuardFn)
  for r in admin.resources do
    let bad = check_resource(r)
    if bad != none then
      panic("admin: {bad}")
    end
  end
  let base = prefix
  -- every route goes through the guard first, then finds its resource
  let wrap = fun(name_of: string, h: fun(Request, Resource) -> Response) -> web.Handler
    fun(req: Request) -> Response
      let refused = guard(req)
      if refused != none then
        return refused
      end
      let r = admin.find(req.params[name_of] ?? "")
      if r == none then
        return problem(404, "no such resource")
      end
      h(req, r)
    end
  end
  let unsafe = fun(h: fun(Request, Resource) -> Response) -> fun(Request, Resource) -> Response
    fun(req: Request, r: Resource) -> Response
      if not csrf_ok(admin, req) then
        return problem(403, "invalid CSRF token")
      end
      h(req, r)
    end
  end
  let token_of = fun(req: Request) -> string
    sess.session_of(req).csrf_token()
  end

  app.get(prefix, fun(req: Request) -> Response
    let refused = guard(req)
    if refused != none then
      return refused
    end
    let items: array<string> = []
    for r in admin.resources do
      items.push("<li><a href=\"{base}/{esc(r.name)}\">{esc(r.title)}</a></li>")
    end
    rendered(base, page_html(admin, "Resources", "<ul>{items.join("")}</ul>"))
  end)

  -- the JSON API
  app.get(prefix + "/api/csrf", fun(req: Request) -> Response
    let refused = guard(req)
    if refused != none then
      return refused
    end
    Response.json(Json.of({"token": token_of(req)}).to_text())
  end)
  app.get(prefix + "/api/:resource", wrap("resource", fun(req: Request, r: Resource) -> Response
    let l = list_rows(admin, r, req)
    if l.is_err() then
      Log.error("admin: {l.unwrap_err().message}")
      return problem(500, "the list could not be read")
    end
    let l2 = l.unwrap()
    Response.json(Json.object({
      "data": Json.array(l2.rows.map(fun(row: map<string, Json>) -> Json Json.object(row) end)),
      "page": number(l2.page),
      "per_page": number(l2.per_page),
      "total": number(l2.total),
      "pages": number(l2.pages),
      }).to_text())
  end))
  app.get(prefix + "/api/:resource/:id", wrap("resource", fun(req: Request, r: Resource) -> Response
    let id = int.parse(req.params["id"] ?? "")
    let row = if id == none then none else find_row(admin, r, id) end
    if row == none then
      return problem(404, "no such row")
    end
    Response.json(Json.object(row).to_text())
  end))
  app.post(prefix + "/api/:resource", wrap("resource", unsafe(fun(req: Request, r: Resource) -> Response
    if not r.can_create then
      return problem(403, "creating is not allowed here")
    end
    let v = values_of(r, json_fields(req), false)
    if not v.errors.is_empty() then
      return problem(422, v.errors.join("; "))
    end
    let made = insert_row(admin, r, v.set)
    if made.is_err() then
      Log.error("admin: {made.unwrap_err().message}")
      return problem(422, "the row could not be saved")
    end
    let row = find_row(admin, r, made.unwrap())
    Response.json(Json.object(row ?? v.set).to_text()).with_status(201)
  end)))
  app.put(prefix + "/api/:resource/:id", wrap("resource", unsafe(fun(req: Request, r: Resource) -> Response
    if not r.can_edit then
      return problem(403, "changing is not allowed here")
    end
    let id = int.parse(req.params["id"] ?? "")
    if id == none or find_row(admin, r, id) == none then
      return problem(404, "no such row")
    end
    let v = values_of(r, json_fields(req), true)
    if not v.errors.is_empty() then
      return problem(422, v.errors.join("; "))
    end
    let done = update_row(admin, r, id, v.set)
    if done.is_err() then
      Log.error("admin: {done.unwrap_err().message}")
      return problem(422, "the row could not be saved")
    end
    Response.json(Json.object(find_row(admin, r, id) ?? {}).to_text())
  end)))
  app.delete(prefix + "/api/:resource/:id", wrap("resource", unsafe(fun(req: Request, r: Resource) -> Response
    if not r.can_delete then
      return problem(403, "deleting is not allowed here")
    end
    let id = int.parse(req.params["id"] ?? "")
    if id == none or find_row(admin, r, id) == none then
      return problem(404, "no such row")
    end
    admin.db.execute("DELETE FROM {r.table} WHERE {r.key} = ?", [number(id)])
    Response.text("").with_status(204)
  end)))

  -- the pages
  app.get(prefix + "/:resource", wrap("resource", fun(req: Request, r: Resource) -> Response
    let l = list_rows(admin, r, req)
    if l.is_err() then
      Log.error("admin: {l.unwrap_err().message}")
      return problem(500, "the list could not be read")
    end
    rendered(base, page_html(admin, r.title, table_html(r, l.unwrap(), req, token_of(req))))
  end))
  app.get(prefix + "/:resource/new", wrap("resource", fun(req: Request, r: Resource) -> Response
    if not r.can_create then
      return problem(403, "creating is not allowed here")
    end
    rendered(base, page_html(admin, "New - {r.title}", form_html(r, "{base}/{r.name}", none, [], {}, token_of(req))))
  end))
  app.post(prefix + "/:resource", wrap("resource", unsafe(fun(req: Request, r: Resource) -> Response
    if not r.can_create then
      return problem(403, "creating is not allowed here")
    end
    let given = form_fields(req)
    let v = values_of(r, given, false)
    if not v.errors.is_empty() then
      return rendered(base, page_html(admin, "New - {r.title}", form_html(r, "{base}/{r.name}", none, v.errors, given, token_of(req)))).with_status(422)
    end
    let made = insert_row(admin, r, v.set)
    if made.is_err() then
      Log.error("admin: {made.unwrap_err().message}")
      return rendered(base, page_html(admin, "New - {r.title}", form_html(r, "{base}/{r.name}", none, ["the row could not be saved"], given, token_of(req)))).with_status(422)
    end
    redirect(base, "/{r.name}")
  end)))
  app.get(prefix + "/:resource/:id/edit", wrap("resource", fun(req: Request, r: Resource) -> Response
    if not r.can_edit then
      return problem(403, "changing is not allowed here")
    end
    let id = int.parse(req.params["id"] ?? "")
    let row = if id == none then none else find_row(admin, r, id) end
    if row == none then
      return problem(404, "no such row")
    end
    rendered(base, page_html(admin, "Edit - {r.title}", form_html(r, "{base}/{r.name}/{id ?? 0}", row, [], {}, token_of(req))))
  end))
  app.post(prefix + "/:resource/:id", wrap("resource", unsafe(fun(req: Request, r: Resource) -> Response
    if not r.can_edit then
      return problem(403, "changing is not allowed here")
    end
    let id = int.parse(req.params["id"] ?? "")
    let row = if id == none then none else find_row(admin, r, id) end
    if row == none or id == none then
      return problem(404, "no such row")
    end
    let given = form_fields(req)
    let v = values_of(r, given, false)
    if not v.errors.is_empty() then
      return rendered(base, page_html(admin, "Edit - {r.title}", form_html(r, "{base}/{r.name}/{id}", row, v.errors, given, token_of(req)))).with_status(422)
    end
    let done = update_row(admin, r, id, v.set)
    if done.is_err() then
      Log.error("admin: {done.unwrap_err().message}")
      return rendered(base, page_html(admin, "Edit - {r.title}", form_html(r, "{base}/{r.name}/{id}", row, ["the row could not be saved"], given, token_of(req)))).with_status(422)
    end
    redirect(base, "/{r.name}")
  end)))
  app.post(prefix + "/:resource/:id/delete", wrap("resource", unsafe(fun(req: Request, r: Resource) -> Response
    if not r.can_delete then
      return problem(403, "deleting is not allowed here")
    end
    let id = int.parse(req.params["id"] ?? "")
    if id != none then
      admin.db.execute("DELETE FROM {r.table} WHERE {r.key} = ?", [number(id)])
    end
    redirect(base, "/{r.name}")
  end)))
end

export Column, Resource, Admin, mount

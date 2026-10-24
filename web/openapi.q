--" # OpenAPI

Writes the OpenAPI 3.1 description of an application from what the routes already say: the
paths and methods, the `#[Path]`, `#[Query]` and `#[Header]` parameters, the `#[Body]` type, the
type each handler returns, `#[Status]`, and the validation annotations of the fields (`Min`,
`Max`, `Length`, `Email`, `Pattern`, `OneOf`).

```
let app = web.App.new(...)
app.controllers(Reflect.callables(controllers))
openapi_route(app, "/openapi.json", "Blog", "1.0.0")   -- GET /openapi.json answers it
```

Add `#[web.Doc("Lists the posts")]` and `#[web.Tag("posts")]` to give a route a summary and a
group. What cannot be known from the code is left out: a field that has a default value is
listed as required when its type is not nullable; a handler that returns a `Response` has no
schema; errors are described by the one shape `Problem` writes.
--"
import "app.q" as web
import "validate.q" as val

--" Collects the structures met while describing types, to put them in `components`. --"
struct Schemas
  public found: map<string, Json>
end

fun nullable_of(schema: Json, nullable: bool) -> Json
  if not nullable then
    return schema
  end
  Json.object({"oneOf": Json.array([schema, Json.object({"type": Json.string("null")})])})
end

fun typed(kind: string) -> Json
  Json.object({"type": Json.string(kind)})
end

fun formatted(kind: string, format: string) -> Json
  Json.object({"type": Json.string(kind), "format": Json.string(format)})
end

--" The schema of a type; structures are put in `schemas` and referred to. --"
fun schema_of(t: TypeInfo, schemas: Schemas) -> Json
  let base = Json.object({})
  if t.kind == "int" then
    base = formatted("integer", "int64")
  end
  if t.kind == "float" then
    base = typed("number")
  end
  if t.kind == "bool" then
    base = typed("boolean")
  end
  if t.kind == "string" then
    base = typed("string")
  end
  if t.kind == "uuid" then
    base = formatted("string", "uuid")
  end
  if t.kind == "ulid" then
    base = typed("string")
  end
  if t.kind == "datetime" then
    base = formatted("string", "date-time")
  end
  if t.kind == "bytes" then
    base = formatted("string", "byte")
  end
  if t.kind == "array" then
    let inner = t.item
    base = Json.object({"type": Json.string("array"), "items": if inner == none then Json.object({}) else schema_of(inner, schemas) end})
  end
  if t.kind == "map" then
    let inner = t.item
    base = Json.object({"type": Json.string("object"), "additionalProperties": if inner == none then Json.object({}) else schema_of(inner, schemas) end})
  end
  if t.kind == "enum" then
    base = Json.object({"type": Json.string("string"), "enum": Json.array(t.variants.map(fun(v: string) -> Json Json.string(v) end))})
  end
  if t.kind == "struct" then
    if schemas.found[t.name] == none and not t.recursive then
      schemas.found[t.name] = Json.object({})
      schemas.found[t.name] = struct_schema(t, schemas)
    end
    base = Json.object({"$ref": Json.string("#/components/schemas/{t.name}")})
  end
  nullable_of(base, t.nullable)
end

fun number_of(a: AnnotationInfo, field: string) -> Json?
  let v = a.get_float(field)
  if v == none then none else Json.number(v) end
end

--" What the validation annotations of a field add to its schema. --"
fun constraints(f: FieldType) -> map<string, Json>
  let extra: map<string, Json> = {}
  let min = f.annotation("Min")
  if min != none then
    let n = number_of(min, "value")
    if n != none then
      extra["minimum"] = n
    end
  end
  let max = f.annotation("Max")
  if max != none then
    let n = number_of(max, "value")
    if n != none then
      extra["maximum"] = n
    end
  end
  let length = f.annotation("Length")
  if length != none then
    let lo = length.get_int("min") ?? 0
    let hi = length.get_int("max") ?? -1
    let array_like = f.info.kind == "array"
    if lo > 0 then
      extra[if array_like then "minItems" else "minLength" end] = Json.number(lo as float)
    end
    if hi >= 0 then
      extra[if array_like then "maxItems" else "maxLength" end] = Json.number(hi as float)
    end
  end
  if f.annotation("NotBlank") != none then
    extra["minLength"] = Json.number(1.0)
  end
  if f.annotation("Email") != none then
    extra["format"] = Json.string("email")
  end
  let pattern = f.annotation("Pattern")
  if pattern != none then
    let r = pattern.get_string("regex")
    if r != none then
      extra["pattern"] = Json.string(r)
    end
  end
  let one_of = f.annotation("OneOf")
  if one_of != none then
    let values = one_of.args["values"]
    if values != none and values.is_array() then
      extra["enum"] = values
    end
  end
  extra
end

fun struct_schema(t: TypeInfo, schemas: Schemas) -> Json
  let props: map<string, Json> = {}
  let required: array<Json> = []
  for f in t.fields do
    props[f.name] = with_constraints(schema_of(f.info, schemas), f)
    if not f.info.nullable then
      required.push(Json.string(f.name))
    end
  end
  let out: map<string, Json> = {"type": Json.string("object"), "properties": Json.object(props)}
  if required.len() > 0 then
    out["required"] = Json.array(required)
  end
  Json.object(out)
end

--" The constraints go next to the type (`minimum`, `maxLength`...) in the same object. A
`$ref` or a nullable schema is wrapped instead. --"
fun with_constraints(schema: Json, f: FieldType) -> Json
  let extra = constraints(f)
  if extra.len() == 0 then
    return schema
  end
  let plain = schema.get("$ref") == none and schema.get("oneOf") == none
  if not plain then
    return Json.object({"allOf": Json.array([schema]), "x-note": Json.string("constrained")})
  end
  let merged: map<string, Json> = {}
  for k in schema.as_object().keys() do
    merged[k] = schema.get(k) ?? Json.null()
  end
  for k in extra.keys() do
    merged[k] = extra[k] ?? Json.null()
  end
  Json.object(merged)
end

fun path_of(pattern: string) -> string
  pattern.split("/").map(fun(seg: string) -> string
    if seg.starts_with(":") then "\{{seg.substring(1, seg.len())}\}" else seg end
  end).join("/")
end

fun name_of(p: ParamInfo, a: AnnotationInfo) -> string
  let given = a.get_string("name") ?? ""
  if given == "" then p.name else given end
end

fun json_content(schema: Json) -> Json
  Json.object({"application/json": Json.object({"schema": schema})})
end

fun error_response(text: string, schemas: Schemas) -> Json
  Json.object({"description": Json.string(text), "content": json_content(schema_of(Reflect.type_info<web.ErrorEnvelope>(), schemas))})
end

--" The operation of one route. --"
fun operation(route: web.RouteDef, c: Callable, schemas: Schemas) -> Json
  let op: map<string, Json> = {"operationId": Json.string(c.name)}
  let doc = c.annotation("Doc")
  if doc != none then
    op["summary"] = Json.string(doc.get_string("summary") ?? "")
    let longer = doc.get_string("description") ?? ""
    if longer != "" then
      op["description"] = Json.string(longer)
    end
  end
  let tag = c.annotation("Tag")
  if tag != none then
    op["tags"] = Json.array([Json.string(tag.get_string("name") ?? "")])
  end
  let params: array<Json> = []
  let responses: map<string, Json> = {}
  let checked = false
  for p in c.params do
    let info = p.type_info()
    let path = p.annotation("Path")
    let query = p.annotation("Query")
    let header = p.annotation("Header")
    let cookie = p.annotation("CookieValue")
    let body = p.annotation("Body")
    if path != none or query != none or header != none or cookie != none then
      let where = "query"
      let name = p.name
      if path != none then
        where = "path"
        name = name_of(p, path)
      end
      if query != none then
        name = name_of(p, query)
      end
      if header != none then
        where = "header"
        name = name_of(p, header)
      end
      if cookie != none then
        where = "cookie"
        name = name_of(p, cookie)
      end
      let required = where == "path" or not info.nullable
      info.nullable = false
      params.push(Json.object({"name": Json.string(name), "in": Json.string(where), "required": Json.boolean(required), "schema": schema_of(info, schemas)}))
      if where == "path" or where == "query" then
        checked = true
      end
    end
    if body != none then
      op["requestBody"] = Json.object({"required": Json.boolean(true), "content": json_content(schema_of(info, schemas))})
      responses["422"] = error_response("The body is not valid", schemas)
      responses["400"] = error_response("The body is not JSON of the right shape", schemas)
    end
  end
  if params.len() > 0 then
    op["parameters"] = Json.array(params)
  end
  if checked and responses["400"] == none then
    responses["400"] = error_response("A parameter cannot be read", schemas)
  end
  let marked = c.annotation("Status")
  let status = 200
  if marked != none then
    status = marked.get_int("code") ?? 200
  end
  let out = c.return_info()
  let shown = out
  if out.kind == "enum" and out.name == "Result" and out.args.len() > 0 then
    shown = out.args[0]
  end
  if shown.kind == "unit" then
    responses["204"] = Json.object({"description": Json.string("No content")})
  else
    let ok: map<string, Json> = {"description": Json.string("Success")}
    if shown.kind != "struct" or shown.name != "Response" then
      ok["content"] = json_content(schema_of(shown, schemas))
    end
    responses["{status}"] = Json.object(ok)
    if shown.nullable or params.len() > 0 and route.pattern.contains(":") then
      responses["404"] = error_response("Not found", schemas)
    end
  end
  op["responses"] = Json.object(responses)
  Json.object(op)
end

--" The OpenAPI document of the routes of `app` (those made from functions or methods). --"
fun openapi(app: web.App, title: string, version: string) -> Json
  let schemas = Schemas { found: {} }
  let paths: map<string, Json> = {}
  let order: array<string> = []
  for route in app.route_list() do
    let c = route.source
    if c == none then
      continue
    end
    let path = path_of(route.pattern)
    let item = paths[path]
    let methods: map<string, Json> = {}
    if item != none and item.is_object() then
      for k in item.as_object().keys() do
        methods[k] = item.get(k) ?? Json.null()
      end
    end
    methods[route.method.lower()] = operation(route, c, schemas)
    paths[path] = Json.object(methods)
  end
  Json.object({
    "openapi": Json.string("3.1.0"),
    "info": Json.object({"title": Json.string(title), "version": Json.string(version)}),
    "paths": Json.object(paths),
    "components": Json.object({"schemas": Json.object(schemas.found)}),
  })
end

--" Adds `GET path` that answers the document (written when the first request comes, so every
route is in it). --"
fun openapi_route(app: web.App, path: string, title: string, version: string)
  let cached: array<string> = []
  app.get(path, fun(req: Request) -> Response
    if cached.len() == 0 then
      cached.push(openapi(app, title, version).to_text())
    end
    Response.json(cached[0])
  end)
end

export openapi, openapi_route, schema_of

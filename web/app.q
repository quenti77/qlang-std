--" # Application: routes, handlers with injected parameters, middleware

A handler is a function. Its parameters say what it needs and where it comes from; the
application fills them in:

```
#[Get("/users/:id")]
fun show(#[Path] id: int, users: UserRepo) -> Result<User, HttpError>
  ...
end

#[Post("/users")]
#[Status(201)]
fun create(#[Body] input: NewUser, users: UserRepo) -> Result<User, HttpError>
  ...
end
```

| Parameter | Filled with |
| --- | --- |
| `#[Path] id: int` | the `:id` of the route, read as the type of the parameter |
| `#[Query] page: int?` | the `?page=` of the URL (`none` when absent if the type allows it) |
| `#[Body] input: NewUser` | the JSON body, read as that type, then validated (`422` otherwise) |
| `#[Header("X-Token")] token: string` | a header of the request |
| `#[CookieValue("sid")] sid: string` | a cookie of the request |
| any other `name: SomeType` | the service of that type (`Request` is the request itself) |

What a handler returns becomes the response: a `Response` as it is; a `string` as text; anything
else as JSON; `none` as `404`; no value as `204`. A `Result` gives its `Ok` the same way and its
`Err` as an error (`HttpError`, `Problem`, or an `Error`, which is a `500` whose details go to the
log, not to the client).

Nothing to list by hand: `App.boot(Reflect.declared(providers).concat(Reflect.declared(controllers)))`
reads what the modules declare (provider functions, `#[di.Service]` structures, route functions and
`#[Controller]` structures) and stops with the list of mistakes of wiring if there are any.

```
let app = App.new(Reflect.callables(providers))
app.controllers(Reflect.callables(controllers))
app.use(logging())
let problems = app.validate()      -- every mistake of wiring, before the first request

fun handle(req: Request) -> Response
  app.handle(req)
end
```
--"
import "container.q" as di
import "validate.q" as val

--" A function from a request to a response. --"
type Handler = fun(Request) -> Response

--" Decides whether a request may go on: `none` lets it through, a response ends it there. --"
type GuardFn = fun(Request) -> Response?

--" Code around a handler: it receives the request and the next handler, and answers. --"
type Middleware = fun(Request, Handler) -> Response

--" `#[Get("/path")]`: this function answers `GET /path`. --"
#[annotation]
struct Get
  path: string
end

--" `#[Controller("/posts")]` on a struct: its methods that carry a route annotation are routes,
all under this prefix. See `App.controller`. --"
#[annotation]
struct Controller
  prefix: string = ""
end

--" `#[Guard("auth")]` on a route or on a controller: the guard of that name (`App.guard`) runs
before the handler, and may answer instead (`401`, a redirect...). Several can be stacked. --"
#[annotation]
struct Guard
  name: string
end

--" `#[Doc("Lists the posts")]`: what a route does, for the generated documentation (`openapi`). --"
#[annotation]
struct Doc
  summary: string
  description: string = ""
end

--" `#[Tag("posts")]`: groups routes in the generated documentation. --"
#[annotation]
struct Tag
  name: string
end

--" `#[Post("/path")]` --"
#[annotation]
struct Post
  path: string
end

--" `#[Put("/path")]` --"
#[annotation]
struct Put
  path: string
end

--" `#[Patch("/path")]` --"
#[annotation]
struct Patch
  path: string
end

--" `#[Delete("/path")]` --"
#[annotation]
struct Delete
  path: string
end

--" `#[Route("/path", method: "OPTIONS")]`: for any other method. --"
#[annotation]
struct Route
  path: string
  method: string = "GET"
end

--" `#[Status(201)]`: the status of a successful answer (200 by default). --"
#[annotation]
struct Status
  code: int
end

--" The parameter comes from the route (`/users/:id`); the name defaults to the parameter's. --"
#[annotation]
struct Path
  name: string = ""
end

--" The parameter comes from the query string; the name defaults to the parameter's. --"
#[annotation]
struct Query
  name: string = ""
end

--" The parameter is the JSON body of the request. --"
#[annotation]
struct Body
end

--" The parameter is a header of the request; the name defaults to the parameter's. --"
#[annotation]
struct Header
  name: string = ""
end

--" The parameter is a cookie of the request; the name defaults to the parameter's. --"
#[annotation]
struct CookieValue
  name: string = ""
end

struct ErrorDetail
  public field: string
  public message: string
end

struct ErrorBody
  public status: int
  public message: string
  public details: array<ErrorDetail>
end

struct ErrorEnvelope
  public error: ErrorBody
end

--" An error answer: a status, a message and, for a refused body, what is wrong with each
field. It is written as `{"error": {"status": 422, "message": "...", "details": [...]}}`. --"
struct Problem
  public status: int
  public message: string
  public details: array<val.FieldError> = []
end

impl Problem
  public fun to_response(self) -> Response
    let details = self.details.map(fun(d: val.FieldError) -> ErrorDetail
      ErrorDetail { field: d.field, message: d.message }
    end)
    let body = ErrorEnvelope { error: ErrorBody { status: self.status, message: self.message, details: details } }
    let r = Response.json(Json.of(body).to_text())
    r.status = self.status
    r
  end
end

type Resolver = fun(Request, di.Container) -> Result<Any, Problem>

--" A route: a method, a pattern and what answers. --"
struct RouteDef
  public method: string
  public pattern: string
  public run: fun(Request, di.Container) -> Response
  public needs: array<string>
  --" The function or method that answers, for routes made from one. --"
  public source: Callable?
  --" The names of the guards that run before it. --"
  public guards: array<string>
end

fun problem<T>(status: int, message: string) -> Result<T, Problem>
  Result<T, Problem>.Err(Problem { status: status, message: message })
end

fun error_response(e: Any) -> Response
  let p = e.as<Problem>()
  if p != none then
    return p.to_response()
  end
  let h = e.as<HttpError>()
  if h != none then
    return Problem { status: h.status, message: h.message }.to_response()
  end
  let plain = e.as<Error>()
  if plain != none then
    Log.error(plain.message)
    return Problem { status: 500, message: "Internal Server Error" }.to_response()
  end
  Log.error("a handler failed with {e.type_name()}")
  Problem { status: 500, message: "Internal Server Error" }.to_response()
end

--" What a handler returned, as a response. --"
fun to_response(a: Any) -> Response
  let r = a.as<Response>()
  if r != none then
    return r
  end
  let text = a.as<string>()
  if text != none then
    return Response.text(text)
  end
  let parts = Reflect.parts(a)
  if parts != none and parts.enum_name == "Result" then
    if parts.variant == "Ok" then
      return to_response(parts.values[0])
    end
    return error_response(parts.values[0])
  end
  if a.type_name() == "no value" then
    return Response { status: 204, body: "" }
  end
  let json = Json.of(a)
  if json.is_null() then
    return Problem { status: 404, message: "Not Found" }.to_response()
  end
  Response.json(json.to_text())
end

fun method_of(c: Callable) -> (string, string)?
  for name in ["Get", "Post", "Put", "Patch", "Delete"] do
    let a = c.annotation(name)
    if a != none then
      let path = a.get_string("path")
      if path != none then
        return (name.upper(), path)
      end
    end
  end
  let r = c.annotation("Route")
  if r != none then
    let path = r.get_string("path")
    let method = r.get_string("method")
    if path != none and method != none then
      return (method.upper(), path)
    end
  end
  none
end

fun name_of(p: ParamInfo, a: AnnotationInfo) -> string
  let given = a.get_string("name")
  if given == none or given == "" then p.name else given end
end

--" A form, unless the body is JSON sent with the default type of `curl -d`. --"
fun is_form(req: Request) -> bool
  let kind = req.header("content-type") ?? ""
  let body = (req.body ?? "").trim()
  kind.lower().starts_with("application/x-www-form-urlencoded") and not body.starts_with("\{") and not body.starts_with("[")
end

--" A form read as the JSON the body type expects: each field is turned into a number or a
boolean when the field of the type is one. Fields that the type does not have are dropped. --"
fun form_json(req: Request, p: ParamInfo) -> Result<Json, Error>
  let form = req.form()
  if form.is_err() then
    return Result<Json, Error>.Err(form.unwrap_err())
  end
  let values = form.unwrap()
  let shape = p.type_info()
  let out: map<string, Json> = {}
  for f in shape.fields do
    let text = values[f.name]
    if text == none then
      if f.info.kind == "bool" then
        out[f.name] = Json.boolean(false)
      end
      continue
    end
    let kind = f.info.kind
    if kind == "int" or kind == "float" then
      let n = float.parse(text)
      if text == "" and f.info.nullable then
        out[f.name] = Json.null()
      else
        if n == none then
          return Result<Json, Error>.Err(Error { message: "{f.name}: {text} is not a number" })
        end
        out[f.name] = Json.number(n)
      end
    else
      if kind == "bool" then
        out[f.name] = Json.boolean(text == "true" or text == "on" or text == "1" or text == "yes")
      else
        if text == "" and f.info.nullable then
          out[f.name] = Json.null()
        else
          out[f.name] = Json.string(text)
        end
      end
    end
  end
  Result<Json, Error>.Ok(Json.object(out))
end

fun optional(p: ParamInfo) -> bool
  p.type_name.ends_with("?")
end

--" The application. --"
struct App
  public container: di.Container
  routes: array<RouteDef>
  middlewares: array<Middleware>
  validator: val.Validator
  base: string
  fallback: Handler?
  chain: Handler?
  wiring: array<string>
  check_bodies: bool
  guards: map<string, GuardFn>
  declared: array<string>
  registered: array<string>
end

impl App
  --" An application whose services come from these provider functions. Functions that carry a
  route annotation are handlers, not providers, and are left out. --"
  public fun new(providers: array<Callable>) -> App
    let services = providers.filter(fun(c: Callable) -> bool method_of(c) == none end)
    let c = di.Container.new(services)
    c.expects<Request>()
    App { container: c, routes: [], middlewares: [], validator: val.Validator.new(), base: "", fallback: none, chain: none, wiring: [], check_bodies: true, guards: {}, declared: [], registered: [] }
  end

  --" Provides every structure marked `#[di.Service]` among these constructors
  (`Reflect.constructors(models)`): its fields are what it needs. --"
  public fun services(self, constructors: array<Callable>)
    self.container.services(constructors)
  end

  --" Says that whoever needs an `I` (a trait) gets the service `T`. --"
  public fun bind<I, T>(self)
    self.container.bind<I, T>()
  end

  --" Names a guard for `#[Guard("name")]`. It receives the request (put what it learns in
  `req.attrs`) and gives `none` to let it through or a response to stop there. --"
  public fun guard(self, name: string, check: GuardFn)
    self.guards[name] = check
  end

  --" The routes added so far, in order. --"
  public fun route_list(self) -> array<RouteDef>
    self.routes
  end

  --" Registers a middleware. The first one added is the outermost. --"
  public fun use(self, m: Middleware)
    self.middlewares.push(m)
    self.chain = none
  end

  --" The routes added from now on start with this path (`"/api"`). --"
  public fun prefix(self, path: string)
    self.base = path
  end

  --" A rule for the validation of bodies: see `Validator.rule`. --"
  public fun rule(self, name: string, check: fun(AnnotationInfo, Any) -> string?)
    self.validator.rule(name, check)
  end

  --" Turns the validation of `#[Body]` parameters on or off (on by default). --"
  public fun validate_bodies(self, on: bool)
    self.check_bodies = on
  end

  --" What answers a request that no route takes (a `404` otherwise). --"
  public fun not_found(self, h: Handler)
    self.fallback = h
  end

  --" Adds a route answered by a plain function of the request. --"
  public fun add(self, method: string, path: string, h: Handler)
    self.routes.push(RouteDef {
      method: method.upper(),
      pattern: self.base + path,
      run: fun(req: Request, c: di.Container) -> Response h(req) end,
      needs: [],
      source: none,
      guards: [],
    })
  end

  public fun get(self, path: string, h: Handler)
    self.add("GET", path, h)
  end

  public fun post(self, path: string, h: Handler)
    self.add("POST", path, h)
  end

  public fun put(self, path: string, h: Handler)
    self.add("PUT", path, h)
  end

  public fun patch(self, path: string, h: Handler)
    self.add("PATCH", path, h)
  end

  public fun delete(self, path: string, h: Handler)
    self.add("DELETE", path, h)
  end

  --" Adds the functions with a route annotation (`#[Get("/x")]`, `#[Route(...)]`) as routes. --"
  public fun controllers(self, handlers: array<Callable>)
    for c in handlers do
      let found = method_of(c)
      if found == none then
        continue
      end
      self.register(c, found.0, self.base + found.1, [])
    end
  end

  --" Adds the public methods of `instance` that carry a route annotation as routes. The struct may
  carry `#[Controller("/prefix")]`. The instance lives as long as the application: what changes
  with each request (the user, a connection) comes in as a parameter of the method, like for a
  function. --"
  public fun controller<T>(self, instance: T)
    if Reflect.type_name<T>().starts_with("array<") then
      panic("App.controller takes one controller (an instance of a struct); for the functions of a module, use App.controllers(Reflect.callables(module))")
    end
    let prefix = ""
    let info = Reflect.struct_info<T>()
    let tag = info.annotation("Controller")
    if tag != none then
      let given = tag.get_string("prefix")
      if given != none then
        prefix = given
      end
    end
    let inherited: array<string> = []
    for a in info.annotations do
      if a.name == "Guard" then
        inherited.push(a.get_string("name") ?? "")
      end
    end
    self.registered.push(Reflect.type_name<T>())
    self.routes_of(Reflect.bound_callables<T>(instance), prefix, inherited)
  end

  fun routes_of(self, methods: array<Callable>, prefix: string, inherited: array<string>)
    for c in methods do
      let found = method_of(c)
      if found == none then
        continue
      end
      let tail = if found.1 == "/" and prefix != "" then "" else found.1 end
      self.register(c, found.0, self.base + prefix + tail, inherited)
    end
  end

  --" Registers what a module declares (`Reflect.declared(module)`): its functions with a route
  annotation, and every structure marked `#[Controller]`, which the container builds from its
  fields (like a `#[di.Service]`) and whose public methods with a route annotation become
  routes. Nothing to list by hand: a controller added to the module is found. --"
  public fun discover(self, declared: array<Callable>)
    self.controllers(declared.filter(fun(c: Callable) -> bool method_of(c) != none end))
    for k in declared do
      if k.annotation("Controller") == none or k.name != k.return_type then
        continue
      end
      if self.container.has_key(k.return_type) == false then
        self.container.provide(k)
      end
      self.registered.push(k.return_type)
      let made = self.container.resolve(k.return_type, [])
      if made.is_err() then
        self.wiring.push("controller {k.return_type}: {made.unwrap_err().message}")
        continue
      end
      let prefix = ""
      let tag = k.annotation("Controller")
      if tag != none then
        prefix = tag.get_string("prefix") ?? ""
      end
      let inherited: array<string> = []
      for a in k.annotations do
        if a.name == "Guard" then
          inherited.push(a.get_string("name") ?? "")
        end
      end
      self.routes_of(Reflect.bound_callables_of(made.unwrap()), prefix, inherited)
    end
  end

  --" Says which structures are controllers (`Reflect.declared(module)`): `validate` reports each
  one that was never registered, with `controller`, `controller_from_container` or `discover`,
  instead of leaving a silent `404`. --"
  public fun declare(self, declared: array<Callable>)
    for k in declared do
      if k.annotation("Controller") != none and k.name == k.return_type then
        self.declared.push(k.return_type)
      end
    end
  end

  --" An application from everything the modules of the project declare, in one call
  (`App.boot(Reflect.declared(providers).concat(Reflect.declared(controllers)))`): the functions
  without a route are providers, the structures marked `#[di.Service]` are services (the other
  structures are plain data), the functions
  with a route annotation and the structures marked `#[Controller]` are the routes. It panics with
  the list of mistakes of wiring if there are any (`validate`), so the application does not start
  half built; `assemble` is the same without that check. --"
  public fun boot(declared: array<Callable>) -> App
    let app = App.assemble(declared)
    let problems = app.validate()
    if not problems.is_empty() then
      panic("the application is not wired correctly:\n  " + problems.join("\n  "))
    end
    app
  end

  --" Like `boot`, without checking the wiring (tests that add services afterwards). --"
  public fun assemble(declared: array<Callable>) -> App
    -- a structure's constructor is named like the structure; a provider function is not
    let app = App.new(declared.filter(fun(c: Callable) -> bool c.name != c.return_type end))
    app.container.services(declared)
    app.declare(declared)
    app.discover(declared)
    app
  end

  --" Like `controller`, with the instance taken from the container (a provider returns `T`). --"
  public fun controller_from_container<T>(self)
    self.registered.push(Reflect.type_name<T>())
    let made = self.container.get<T>()
    if made.is_err() then
      self.wiring.push("controller {Reflect.type_name<T>()}: {made.unwrap_err().message}")
      return
    end
    self.controller<T>(made.unwrap())
  end

  fun register(self, c: Callable, method: string, pattern: string, inherited: array<string>)
    let guard_names: array<string> = []
    for g in inherited do
      guard_names.push(g)
    end
    for a in c.annotations do
      if a.name == "Guard" then
        guard_names.push(a.get_string("name") ?? "")
      end
    end
    let app = self
    let resolvers: array<Resolver> = []
    let needs: array<string> = []
    for p in c.params do
      let made = self.resolver_for(p, pattern)
      if made.is_err() then
        self.wiring.push("{method} {pattern}: {made.unwrap_err()}")
        return
      end
      resolvers.push(made.unwrap())
      if self.is_service(p) then
        needs.push(p.type_name)
      end
    end
    let status = c.annotation("Status")
    let code = 0
    if status != none then
      let given = status.get_int("code")
      if given != none then
        code = given
      end
    end
    self.routes.push(RouteDef {
      method: method,
      pattern: pattern,
      run: fun(req: Request, parent: di.Container) -> Response
        for g in guard_names do
          let check = app.guards[g]
          if check == none then
            Log.error("{c.name}: no guard called {g}")
            return Problem { status: 500, message: "Internal Server Error" }.to_response()
          end
          let stop = check(req)
          if stop != none then
            return stop
          end
        end
        let scope = parent.child()
        scope.set(req)
        let args: array<Any> = []
        for r in resolvers do
          let a = r(req, scope)
          if a.is_err() then
            return a.unwrap_err().to_response()
          end
          args.push(a.unwrap())
        end
        let out = c.call(args)
        if out.is_err() then
          Log.error("{c.name}: {out.unwrap_err().message}")
          return Problem { status: 500, message: "Internal Server Error" }.to_response()
        end
        let res = to_response(out.unwrap())
        if code != 0 and res.status == 200 then
          res.status = code
        end
        res
      end,
      needs: needs,
      source: c,
      guards: guard_names,
    })
  end

  fun is_service(self, p: ParamInfo) -> bool
    p.annotation("Path") == none and p.annotation("Query") == none and p.annotation("Body") == none and p.annotation("Header") == none and p.annotation("CookieValue") == none
  end

  fun resolver_for(self, p: ParamInfo, pattern: string) -> Result<Resolver, string>
    let validator = self.validator
    let check_bodies = self.check_bodies
    let path = p.annotation("Path")
    if path != none then
      let name = name_of(p, path)
      if not pattern.contains(":{name}") then
        return Result<Resolver, string>.Err("#[Path] {name} is not a parameter of the route")
      end
      return Result<Resolver, string>.Ok(fun(req: Request, c: di.Container) -> Result<Any, Problem>
        let text = req.params[name]
        if text == none then
          return problem<Any>(500, "route parameter {name} is missing")
        end
        let read = p.parse(text)
        if read.is_err() then
          return problem<Any>(400, "path parameter {name}: {read.unwrap_err().message}")
        end
        Result<Any, Problem>.Ok(read.unwrap())
      end)
    end
    let query = p.annotation("Query")
    if query != none then
      let name = name_of(p, query)
      return Result<Resolver, string>.Ok(fun(req: Request, c: di.Container) -> Result<Any, Problem>
        let text = req.query[name]
        if text == none and not optional(p) then
          return problem<Any>(400, "query parameter {name} is required")
        end
        let read = p.parse(if text == none then "" else text end)
        if read.is_err() then
          return problem<Any>(400, "query parameter {name}: {read.unwrap_err().message}")
        end
        Result<Any, Problem>.Ok(read.unwrap())
      end)
    end
    let header = p.annotation("Header")
    if header != none then
      let name = name_of(p, header)
      return Result<Resolver, string>.Ok(fun(req: Request, c: di.Container) -> Result<Any, Problem>
        let text = req.header(name)
        if text == none and not optional(p) then
          return problem<Any>(400, "header {name} is required")
        end
        let read = p.parse(if text == none then "" else text end)
        if read.is_err() then
          return problem<Any>(400, "header {name}: {read.unwrap_err().message}")
        end
        Result<Any, Problem>.Ok(read.unwrap())
      end)
    end
    let cookie = p.annotation("CookieValue")
    if cookie != none then
      let name = name_of(p, cookie)
      return Result<Resolver, string>.Ok(fun(req: Request, c: di.Container) -> Result<Any, Problem>
        let text = req.cookies[name]
        if text == none and not optional(p) then
          return problem<Any>(400, "cookie {name} is required")
        end
        let read = p.parse(if text == none then "" else text end)
        if read.is_err() then
          return problem<Any>(400, "cookie {name}: {read.unwrap_err().message}")
        end
        Result<Any, Problem>.Ok(read.unwrap())
      end)
    end
    if p.annotation("Body") != none then
      return Result<Resolver, string>.Ok(fun(req: Request, c: di.Container) -> Result<Any, Problem>
        let text = req.body
        if text == none or text.trim().is_empty() then
          if optional(p) then
            return Result<Any, Problem>.Ok(Any.of(""))
          end
          return problem<Any>(400, "the request needs a body")
        end
        let tree = if is_form(req) then form_json(req, p) else Json.parse(text) end
        if tree.is_err() then
          return problem<Any>(400, "the body is not valid: {tree.unwrap_err().message}")
        end
        let read = p.decode(tree.unwrap())
        if read.is_err() then
          return problem<Any>(422, read.unwrap_err().message)
        end
        let value = read.unwrap()
        if check_bodies then
          let errors = validator.check(value)
          if not errors.is_empty() then
            return Result<Any, Problem>.Err(Problem { status: 422, message: "validation failed", details: errors })
          end
        end
        Result<Any, Problem>.Ok(value)
      end)
    end
    -- anything else is a service
    let key = p.type_name
    Result<Resolver, string>.Ok(fun(req: Request, c: di.Container) -> Result<Any, Problem>
      let made = c.resolve(key, [])
      if made.is_err() then
        Log.error(made.unwrap_err().message)
        return problem<Any>(500, "Internal Server Error")
      end
      Result<Any, Problem>.Ok(made.unwrap())
    end)
  end

  --" Every mistake of wiring, as texts (empty when all is well): handlers that cannot be built,
  services that are missing or in a cycle, routes hidden by an earlier one. Call it when the
  application starts. --"
  public fun validate(self) -> array<string>
    let problems: array<string> = []
    for w in self.wiring do
      problems.push(w)
    end
    for p in self.container.validate() do
      problems.push(p)
    end
    for d in self.declared do
      if not self.registered.contains(d) then
        problems.push("controller {d} is declared but never registered: its routes answer 404")
      end
    end
    let i = 0
    for route in self.routes do
      for g in route.guards do
        if self.guards[g] == none then
          problems.push("{route.method} {route.pattern} has the guard {g}, which was not defined")
        end
      end
      for need in route.needs do
        if need != "Request" and not self.container.has_key(need) then
          problems.push("{route.method} {route.pattern} needs {need}: no provider")
        end
      end
      let j = 0
      for earlier in self.routes do
        if j >= i then
          break
        end
        if earlier.method == route.method and Router.matches(earlier.pattern, route.pattern) != none then
          problems.push("{route.method} {route.pattern} is hidden by {earlier.pattern}")
        end
        j += 1
      end
      i += 1
    end
    problems
  end

  fun dispatch(self, req: Request) -> Response
    let allowed: array<string> = []
    for route in self.routes do
      let found = Router.matches(route.pattern, req.path)
      if found == none then
        continue
      end
      if route.method == req.method or (route.method == "GET" and req.method == "HEAD") then
        req.params = found
        req.attrs["route"] = Any.of(route.pattern)
        return route.run(req, self.container)
      end
      if not allowed.contains(route.method) then
        allowed.push(route.method)
      end
    end
    if not allowed.is_empty() then
      let r = Problem { status: 405, message: "Method Not Allowed" }.to_response()
      r.headers["Allow"] = allowed.join(", ")
      return r
    end
    let other = self.fallback
    if other != none then
      return other(req)
    end
    Problem { status: 404, message: "Not Found" }.to_response()
  end

  --" The response to a request: the middleware, then the route that takes it. --"
  public fun handle(self, req: Request) -> Response
    let built = self.chain
    if built != none then
      return built(req)
    end
    let top: Handler = fun(r: Request) -> Response self.dispatch(r) end
    let i = self.middlewares.len() - 1
    while i >= 0 do
      let m = self.middlewares[i]
      let inner = top
      top = fun(r: Request) -> Response m(r, inner) end
      i -= 1
    end
    self.chain = top
    top(req)
  end
end

export App, ErrorEnvelope, Problem, Handler, Middleware, RouteDef, to_response
export Get, Post, Put, Patch, Delete, Route, Controller, Guard, GuardFn, Doc, Tag, Status, Path, Query, Body, Header, CookieValue

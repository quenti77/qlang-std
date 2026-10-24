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
end

impl App
  --" An application whose services come from these provider functions. Functions that carry a
  route annotation are handlers, not providers, and are left out. --"
  public fun new(providers: array<Callable>) -> App
    let services = providers.filter(fun(c: Callable) -> bool method_of(c) == none end)
    let c = di.Container.new(services)
    c.expects<Request>()
    App { container: c, routes: [], middlewares: [], validator: val.Validator.new(), base: "", fallback: none, chain: none, wiring: [], check_bodies: true }
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
      self.register(c, found.0, self.base + found.1)
    end
  end

  --" Adds the public methods of `instance` that carry a route annotation as routes. The struct may
  carry `#[Controller("/prefix")]`. The instance lives as long as the application: what changes
  with each request (the user, a connection) comes in as a parameter of the method, like for a
  function. --"
  public fun controller<T>(self, instance: T)
    let prefix = ""
    let info = Reflect.struct_info<T>()
    let tag = info.annotation("Controller")
    if tag != none then
      let given = tag.get_string("prefix")
      if given != none then
        prefix = given
      end
    end
    for c in Reflect.bound_callables<T>(instance) do
      let found = method_of(c)
      if found == none then
        continue
      end
      let tail = if found.1 == "/" and prefix != "" then "" else found.1 end
      self.register(c, found.0, self.base + prefix + tail)
    end
  end

  --" Like `controller`, with the instance taken from the container (a provider returns `T`). --"
  public fun controller_from_container<T>(self)
    let made = self.container.get<T>()
    if made.is_err() then
      self.wiring.push("controller {Reflect.type_name<T>()}: {made.unwrap_err().message}")
      return
    end
    self.controller<T>(made.unwrap())
  end

  fun register(self, c: Callable, method: string, pattern: string)
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
        let json = Json.parse(text)
        if json.is_err() then
          return problem<Any>(400, "the body is not valid JSON: {json.unwrap_err().message}")
        end
        let read = p.decode(json.unwrap())
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
    let i = 0
    for route in self.routes do
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

export App, Problem, Handler, Middleware, RouteDef, to_response
export Get, Post, Put, Patch, Delete, Route, Controller, Status, Path, Query, Body, Header, CookieValue

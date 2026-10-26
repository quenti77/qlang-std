--" # Dependency container

A function that returns a `T` *provides* a `T`; its parameters are what it needs. The
container finds each provider by the type it returns, builds the services the first time they
are asked for, and checks the whole graph (missing services, cycles, a long-lived service
holding a short-lived one) when you call `validate`, before the first request.

```
-- providers.q
fun make_config() -> Config ... end
fun make_users(config: Config, db: Db) -> UserRepo ... end

-- main.q
import "providers.q" as providers
let app = Container.new(Reflect.callables(providers))
let users = app.get<UserRepo>().unwrap()
```

Lifetimes: a provider is a *singleton* (built once) unless it carries `#[Scoped]` (built once per
request, see `child`) or `#[Transient]` (built every time).

A structure can be a service without a provider: mark it `#[Service]` and its fields are what
it needs, filled in by the container (private fields too):

```
#[Service]
struct Users
  db: Db
end

app.services(Reflect.constructors(models))   -- every `#[Service]` structure of `models`
app.bind<Mailer, ResendMailer>()             -- `Mailer` is whatever `ResendMailer` is
```
--"

--" Marks a structure as a service: the container builds it from its fields (see
`Container.services`). `#[Scoped]` and `#[Transient]` go next to it. --"
#[annotation]
struct Service
end

--" The constructors (`Reflect.constructors(module)`) of the structures marked `#[Service]`: add
them to the providers of something that takes a list (`Cli.new(Reflect.callables(providers)
.concat(services_of(Reflect.constructors(providers))))`). --"
fun services_of(constructors: array<Callable>) -> array<Callable>
  constructors.filter(fun(c: Callable) -> bool c.annotation("Service") != none end)
end

--" Marks a provider whose service is built once for each request (each `child` container). --"
#[annotation]
struct Scoped
end

--" Marks a provider whose service is built again each time it is asked for. --"
#[annotation]
struct Transient
end

--" A provider the container knows: the type it gives, how long the service lives, what it needs. --"
struct Provider
  public key: string
  public lifetime: string
  public needs: array<string>
  public maker: Callable?
  --" When not empty: this service is the one called `alias` (see `bind`). --"
  public alias: string
end

--" Services, built from providers. --"
struct Container
  providers: map<string, Provider>
  instances: map<string, Any>
  parent: Container?
  external: array<string>
end

fun container_error<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
end

fun lifetime_of(c: Callable) -> string
  if c.annotation("Scoped") != none then
    return "scoped"
  end
  if c.annotation("Transient") != none then
    return "transient"
  end
  "singleton"
end

impl Container
  --" A container whose providers are the given functions (`Reflect.callables(module)`). --"
  public fun new(callables: array<Callable>) -> Container
    let table: map<string, Provider> = {}
    for c in callables do
      let needs: array<string> = []
      for p in c.params do
        needs.push(p.type_name)
      end
      table[c.return_type] = Provider { key: c.return_type, lifetime: lifetime_of(c), needs: needs, maker: c, alias: "" }
    end
    Container { providers: table, instances: {}, parent: none, external: [] }
  end

  --" Adds a provider function (`Reflect.callable("name")`). --"
  public fun provide(self, c: Callable)
    let needs: array<string> = []
    for p in c.params do
      needs.push(p.type_name)
    end
    self.providers[c.return_type] = Provider { key: c.return_type, lifetime: lifetime_of(c), needs: needs, maker: c, alias: "" }
  end

  --" Provides every structure marked `#[Service]` among the constructors
(`Reflect.constructors(module)`): its fields are its dependencies. --"
  public fun services(self, constructors: array<Callable>)
    for c in constructors do
      if c.annotation("Service") != none then
        self.provide(c)
      end
    end
  end

  --" Says that the service `I` (usually a trait) is the service `T`: whoever needs an `I` gets
  the `T`. Tests bind the same `I` to another one. --"
  public fun bind<I, T>(self)
    let target = Reflect.type_name<T>()
    let life = self.providers[target]
    self.providers[Reflect.type_name<I>()] = Provider {
      key: Reflect.type_name<I>(),
      lifetime: if life == none then "singleton" else life.lifetime end,
      needs: [target],
      maker: none,
      alias: target,
    }
  end

  --" Puts a ready value in the container: it is the service of its type (a test double, a
  configuration read at start). --"
  public fun set<T>(self, value: T)
    self.instances[Reflect.type_name<T>()] = Any.of(value)
  end

  --" Says that services of this type will come from elsewhere (the request, set on each
  `child`): `validate` does not complain about them. --"
  public fun expects<T>(self)
    self.external.push(Reflect.type_name<T>())
  end

  --" A container for one request: it sees every service of this one, builds the `#[Scoped]`
  ones for itself, and takes what `set` puts in it. --"
  public fun child(self) -> Container
    Container { providers: self.providers, instances: {}, parent: self, external: self.external }
  end

  --" Whether a service of this type can be given. --"
  public fun has<T>(self) -> bool
    self.has_key(Reflect.type_name<T>())
  end

  --" Whether a service with this type name can be given (see `has`). --"
  public fun has_key(self, key: string) -> bool
    if self.instances[key] != none or self.providers[key] != none then
      return true
    end
    let up = self.parent
    if up != none then
      return up.has_key(key)
    end
    false
  end

  --" The service of type `T`, built if it was not yet; `err` says what is missing. --"
  public fun get<T>(self) -> Result<T, Error>
    let key = Reflect.type_name<T>()
    let made = self.resolve(key, [])
    if made.is_err() then
      return Result<T, Error>.Err(made.unwrap_err())
    end
    let any = made.unwrap()
    let value = any.as<T>()
    if value == none then
      return container_error<T>("{key} was provided as {any.type_name()}")
    end
    Result<T, Error>.Ok(value)
  end

  --" The service called `key` (a type name), as an `Any`. `path` is what is being built, to
  catch a service that needs itself. --"
  public fun resolve(self, key: string, path: array<string>) -> Result<Any, Error>
    let known = self.instances[key]
    if known != none then
      return Result<Any, Error>.Ok(known)
    end
    let provider = self.providers[key]
    if provider == none then
      let up = self.parent
      if up != none then
        return up.resolve(key, path)
      end
      let by = path.last()
      if by == none then
        return container_error<Any>("no service of type {key}")
      end
      return container_error<Any>("no service of type {key} (needed by {by})")
    end
    if path.contains(key) then
      let chain = path.join(" -> ")
      return container_error<Any>("{key} needs itself: {chain} -> {key}")
    end
    -- a singleton lives in the root container, whoever asks
    let up = self.parent
    if up != none and provider.lifetime == "singleton" then
      return up.resolve(key, path)
    end
    if up == none and provider.lifetime == "scoped" then
      return container_error<Any>("{key} is scoped: ask a child container (one per request) for it")
    end
    if provider.alias != "" then
      return self.resolve(provider.alias, path.concat([key]))
    end
    let maker = provider.maker
    if maker == none then
      return container_error<Any>("{key} has no way to be built")
    end
    let args: array<Any> = []
    let next = path.concat([key])
    for need in provider.needs do
      let dep = self.resolve(need, next)
      if dep.is_err() then
        return dep
      end
      args.push(dep.unwrap())
    end
    let built = maker.call(args)
    if built.is_err() then
      return container_error<Any>("{key}: {built.unwrap_err().message}")
    end
    let service = built.unwrap()
    if provider.lifetime != "transient" then
      self.instances[key] = service
    end
    Result<Any, Error>.Ok(service)
  end

  --" Checks every provider without building anything: what is missing, what needs itself, and
  what lives longer than what it holds. The mistakes, one text each; empty when all is well. Call
  it once when the application starts. --"
  public fun validate(self) -> array<string>
    let problems: array<string> = []
    let keys = self.providers.keys()
    keys.sort()
    for key in keys do
      let p = self.providers[key]
      if p == none then
        continue
      end
      for need in p.needs do
        if self.external.contains(need) or self.instances[need] != none then
          if p.lifetime == "singleton" and self.external.contains(need) then
            problems.push("{key} is a singleton but needs {need}, which changes with every request")
          end
          continue
        end
        let dep = self.providers[need]
        if dep == none then
          problems.push("{key} needs {need}: no provider")
          continue
        end
        if p.lifetime == "singleton" and dep.lifetime != "singleton" then
          problems.push("{key} is a singleton but needs {need}, which is {dep.lifetime}")
        end
      end
      let cycle = self.cycle_from(key, [])
      if cycle != none then
        problems.push("cycle: {cycle}")
      end
    end
    problems
  end

  fun cycle_from(self, key: string, path: array<string>) -> string?
    if path.contains(key) then
      let chain = path.join(" -> ")
      return "{chain} -> {key}"
    end
    let p = self.providers[key]
    if p == none then
      return none
    end
    let next = path.concat([key])
    for need in p.needs do
      let found = self.cycle_from(need, next)
      if found != none then
        return found
      end
    end
    none
  end
end

export Container, Provider, Scoped, Transient, Service, services_of

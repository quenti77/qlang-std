# cli.q

## `struct Command`

`#[Command("db:migrate", "Runs the migrations")]`: this function is a command.

## `struct Arg`

`#[Arg]`: a positional argument. The name shown in the usage defaults to the parameter's.

## `struct Opt`

`#[Opt(name: "count", short: "c", description: "...")]`: an option `--count` (`-c`).

## `struct Console`

What a command talks to: standard output and input, or lists in memory for a test.

**Fields**

- `out: array<string>`
- `err: array<string>`

**Methods**

- `fun stdio() -> Console` — The terminal: `line` prints, `error` writes on the error output, `ask` reads.
- `fun captured(answers: array<string>) -> Console` — A console that keeps what is written; `answers` are what `ask` and `confirm` receive.
- `fun line(text: string)`
- `fun error(text: string)`
- `fun output() -> string` — Everything `line` wrote (captured console), one line each.
- `fun errors() -> string` — Everything `error` wrote (captured console).
- `fun ask(question: string) -> string` — Shows the question and gives the line the user types.
- `fun confirm(question: string, fallback: bool) -> bool` — Asks a yes/no question; an empty answer is `fallback`.
- `fun table(headers: array<string>, rows: array<array<string>>)` — A table: the headers, a line of dashes, then the rows, each column as wide as its widest cell.

## `struct Param`

One parameter of a command, as the command line sees it.

**Fields**

- `info: ParamInfo`
- `kind: string` — `arg`, `opt` or `service`.
- `name: string`
- `short: string`
- `description: string`
- `flag: bool`
- `many: bool`
- `optional: bool`

## `struct CommandDef`

A command found by its annotation.

**Fields**

- `name: string`
- `description: string`
- `params: array<Param>`
- `run: Callable`

## `struct Cli`

The set of commands of a program.

**Fields**

- `container: Container`
- `program: string`

**Methods**

- `fun new(providers: array<Callable>) -> Cli` — A program whose services come from these provider functions (may be empty).
- `fun named(program: string)` — The name of the program in the usage lines.
- `fun add(found: array<Callable>)` — Adds the functions that carry `#[Command]`.
- `fun validate() -> array<string>` — What is wrong with the commands: duplicate names, an `Arg` after an array `Arg`, a service that no provider gives. Empty when all is well.
- `fun list(console: Console)` — The list of commands, grouped by the part before the colon.
- `fun usage(c: CommandDef, console: Console)` — The usage of one command: its form, then its arguments and options.
- `fun main()` — Runs the program with its arguments (`env.args()`) on the terminal and ends the process with the exit code.
- `fun run(args: array<string>, console: Console) -> int` — Runs one command line and gives its exit code: `0` all went well, `1` the command failed, `2` the command line is wrong, `127` no such command. Nothing is written but on `console`.

# csv.q

## `fun parse(text: string) -> Result<array<array<string>>, Error>`

Reads CSV text separated by commas: one array of fields for each line. An empty line is a
line with one empty field; a final new line does not make an extra line. `err` when a quoted
field is never closed.

## `fun parse_with(text: string, delimiter: string) -> Result<array<array<string>>, Error>`

Like `parse`, with another separator: one character, such as `";"` or `"\t"`.

## `fun parse_records(text: string) -> Result<array<map<string, string>>, Error>`

Reads CSV text whose first line names the columns: one map for each following line, from
the name of a column to the field. A line with fewer fields than the header has empty strings
for the missing ones; extra fields are dropped.

## `fun to_records(rows: array<array<string>>) -> Result<array<map<string, string>>, Error>`

The same as `parse_records` for rows already read.

## `fun to_text(rows: array<array<string>>) -> string`

CSV text for these rows, separated by commas, each line ending with `\n`. A field is
quoted only when it has to be (it holds the separator, a quote, or a new line).

## `fun to_text_with(rows: array<array<string>>, delimiter: string) -> string`

Like `to_text`, with another one-character separator.

# i18n.q

## `struct Translator`

Messages by language.

**Fields**

- `default_locale: string`
- `messages: map<string, map<string, string>>`
- `rules: map<string, fun(int) -> string>`

**Methods**

- `fun new(default_locale: string) -> Translator` — A translator whose fallback language is `default_locale`.
- `fun add(locale: string, key: string, message: string)` — Sets (or replaces) one message. For plural forms, add `key#one`, `key#other`...
- `fun plural_rule(language: string, rule: fun(int) -> string)` — Uses another plural rule for a language (`one`, `few`, `many`, `other`...).
- `fun add_json(locale: string, text: string) -> Result<int, Error>` — Adds the messages of a JSON text. `err` when it is not an object of messages.
- `fun load(locale: string, path: string) -> Result<int, Error>` — Reads the messages of `locale` from a JSON file.
- `fun chain(locale: string) -> array<string>` — The locales tried for `locale`, most specific first, ending with the default.
- `fun has(locale: string, key: string) -> bool` — Whether a message exists for `key` in `locale` or a fallback.
- `fun t(locale: string, key: string, params: map<string, string>) -> string` — The message, with `{name}` placeholders filled from `params`; the key when there is none.
- `fun tn(locale: string, key: string, count: int, params: map<string, string>) -> string` — The message for `count`, in the plural form of the language. `{count}` is filled in too.
- `fun number(locale: string, value: float, decimals: int) -> string` — A number written as the language does: `1 234,50` in French, `1,234.50` in English, `1.234,50` in German and Spanish.
- `fun missing(locale: string) -> array<string>` — The keys the default language has and `locale` lacks: what is left to translate.
- `fun negotiate(accept_language: string?, available: array<string>) -> string` — The language of a request: the best of `available` that `accept_language` (the header `Accept-Language`) asks for, by quality, or the default language.
- `fun lang(locale: string) -> Lang` — The language `locale` as a `Lang`, to translate without repeating it.
- `fun locales() -> array<string>` — The locales that have messages.

## `struct Lang`

A language chosen once, to translate without repeating it.

**Fields**

- `locale: string`
- `translator: Translator`

**Methods**

- `fun t(key: string, params: map<string, string>) -> string`
- `fun tn(key: string, count: int, params: map<string, string>) -> string`
- `fun number(value: float, decimals: int) -> string`

## `fun language_of(locale: string) -> string`

The language part of a tag: `fr` for `fr-CA` and `fr_CA`.

## `fun plural_rule(language: string, n: int) -> string`

The built-in plural rule of a language.

# template.q

## `fun render(source: string, data: Json) -> Result<string, Error>`

Fills the template with `data` (a `Json` object). `err` if the template is wrong, or prints a
value that does not exist.

## `fun render_html(source: string, data: Json) -> Result<string, Error>`

Like `render`, for HTML: what `{{ }}` prints is escaped, unless its last filter is `raw`.

## `fun render_text(source: string, values: map<string, string>) -> Result<string, Error>`

Like `render`, for plain texts only: `values` maps names to strings.

# toml.q

## `fun parse(text: string) -> Result<Json, Error>`

Reads TOML text into a `Json` object. `err`, with the line, when the text is not valid TOML
(or uses something this reader does not do: the dates stay text, and the keys are not checked for
all the fine points of the format).

# web/app.q

## `struct Get`

`#[Get("/path")]`: this function answers `GET /path`.

## `struct Controller`

`#[Controller("/posts")]` on a struct: its methods that carry a route annotation are routes,
all under this prefix. See `App.controller`.

## `struct Doc`

`#[Doc("Lists the posts")]`: what a route does, for the generated documentation (`openapi`).

## `struct Tag`

`#[Tag("posts")]`: groups routes in the generated documentation.

## `struct Post`

`#[Post("/path")]`

## `struct Put`

`#[Put("/path")]`

## `struct Patch`

`#[Patch("/path")]`

## `struct Delete`

`#[Delete("/path")]`

## `struct Route`

`#[Route("/path", method: "OPTIONS")]`: for any other method.

## `struct Status`

`#[Status(201)]`: the status of a successful answer (200 by default).

## `struct Path`

The parameter comes from the route (`/users/:id`); the name defaults to the parameter's.

## `struct Query`

The parameter comes from the query string; the name defaults to the parameter's.

## `struct Body`

The parameter is the JSON body of the request.

## `struct Header`

The parameter is a header of the request; the name defaults to the parameter's.

## `struct CookieValue`

The parameter is a cookie of the request; the name defaults to the parameter's.

## `struct ErrorEnvelope`

**Fields**

- `error: ErrorBody`

## `struct Problem`

An error answer: a status, a message and, for a refused body, what is wrong with each
field. It is written as `{"error": {"status": 422, "message": "...", "details": [...]}}`.

**Fields**

- `status: int`
- `message: string`
- `details: array<FieldError>`

**Methods**

- `fun to_response() -> Response`

## `struct RouteDef`

A route: a method, a pattern and what answers.

**Fields**

- `method: string`
- `pattern: string`
- `run: fun(Request, Container) -> Response`
- `needs: array<string>`
- `source: Callable?` — The function or method that answers, for routes made from one.

## `fun to_response(a: Any) -> Response`

What a handler returned, as a response.

## `struct App`

The application.

**Fields**

- `container: Container`

**Methods**

- `fun new(providers: array<Callable>) -> App` — An application whose services come from these provider functions. Functions that carry a route annotation are handlers, not providers, and are left out.
- `fun route_list() -> array<RouteDef>` — The routes added so far, in order.
- `fun use(m: fun(Request, fun(Request) -> Response) -> Response)` — Registers a middleware. The first one added is the outermost.
- `fun prefix(path: string)` — The routes added from now on start with this path (`"/api"`).
- `fun rule(name: string, check: fun(AnnotationInfo, Any) -> string?)` — A rule for the validation of bodies: see `Validator.rule`.
- `fun validate_bodies(on: bool)` — Turns the validation of `#[Body]` parameters on or off (on by default).
- `fun not_found(h: fun(Request) -> Response)` — What answers a request that no route takes (a `404` otherwise).
- `fun add(method: string, path: string, h: fun(Request) -> Response)` — Adds a route answered by a plain function of the request.
- `fun get(path: string, h: fun(Request) -> Response)`
- `fun post(path: string, h: fun(Request) -> Response)`
- `fun put(path: string, h: fun(Request) -> Response)`
- `fun patch(path: string, h: fun(Request) -> Response)`
- `fun delete(path: string, h: fun(Request) -> Response)`
- `fun controllers(handlers: array<Callable>)` — Adds the functions with a route annotation (`#[Get("/x")]`, `#[Route(...)]`) as routes.
- `fun controller(instance: T)` — Adds the public methods of `instance` that carry a route annotation as routes. The struct may carry `#[Controller("/prefix")]`. The instance lives as long as the application: what changes with each request (the user, a connection) comes in as a parameter of the method, like for a function.
- `fun controller_from_container()` — Like `controller`, with the instance taken from the container (a provider returns `T`).
- `fun validate() -> array<string>` — Every mistake of wiring, as texts (empty when all is well): handlers that cannot be built, services that are missing or in a cycle, routes hidden by an earlier one. Call it when the application starts.
- `fun handle(req: Request) -> Response` — The response to a request: the middleware, then the route that takes it.

# web/cache.q

## `trait Store`

Where a cache keeps its texts. `ttl` is in seconds; the store drops an entry once it is older.

## `struct MemoryStore`

A store in the memory of the worker.

**Methods**

- `fun new() -> MemoryStore`
- `fun read(key: string) -> string?`
- `fun write(key: string, value: string, ttl: int)`
- `fun drop(key: string)`

## `struct FileStore`

A store with a file per key in `dir`, which must exist. The first line of a file is the
moment (milliseconds) its entry expires.

**Methods**

- `fun new(dir: string) -> FileStore`
- `fun read(key: string) -> string?`
- `fun write(key: string, value: string, ttl: int)`
- `fun drop(key: string)`

## `struct Cache`

A cache over a store.

**Methods**

- `fun new(store: Store) -> Cache`
- `fun memory() -> Cache` — A cache in the memory of the worker.
- `fun files(dir: string) -> Cache` — A cache in files of `dir` (shared by the workers).
- `fun scoped(name: string) -> Cache` — The same store, with `name:` put before every key (one cache per feature).
- `fun get_text(key: string) -> string?` — The text under `key`, or `none` when there is none or it has expired.
- `fun put_text(key: string, value: string, ttl: int)`
- `fun get(key: string) -> T?` — The value under `key` read as a `T`, or `none` (absent, expired, or not a `T`).
- `fun put(key: string, value: T, ttl: int)` — Keeps `value` for `ttl` seconds.
- `fun forget(key: string)` — Forgets `key`.
- `fun has(key: string) -> bool`
- `fun remember(key: string, ttl: int, produce: fun() -> T) -> T` — The value under `key`; when there is none, `produce()` makes it and it is kept for `ttl` seconds.

# web/commands.q

## `struct Migrations`

The migrations of the application, as a service.

**Fields**

- `list: array<Migration>`

# web/container.q

## `struct Scoped`

Marks a provider whose service is built once for each request (each `child` container).

## `struct Transient`

Marks a provider whose service is built again each time it is asked for.

## `struct Provider`

A provider the container knows: the type it gives, how long the service lives, what it needs.

**Fields**

- `key: string`
- `lifetime: string`
- `needs: array<string>`
- `maker: Callable`

## `struct Container`

Services, built from providers.

**Methods**

- `fun new(callables: array<Callable>) -> Container` — A container whose providers are the given functions (`Reflect.callables(module)`).
- `fun provide(c: Callable)` — Adds a provider function (`Reflect.callable("name")`).
- `fun set(value: T)` — Puts a ready value in the container: it is the service of its type (a test double, a configuration read at start).
- `fun expects()` — Says that services of this type will come from elsewhere (the request, set on each `child`): `validate` does not complain about them.
- `fun child() -> Container` — A container for one request: it sees every service of this one, builds the `#[Scoped]` ones for itself, and takes what `set` puts in it.
- `fun has() -> bool` — Whether a service of this type can be given.
- `fun has_key(key: string) -> bool` — Whether a service with this type name can be given (see `has`).
- `fun get() -> Result<T, Error>` — The service of type `T`, built if it was not yet; `err` says what is missing.
- `fun resolve(key: string, path: array<string>) -> Result<Any, Error>` — The service called `key` (a type name), as an `Any`. `path` is what is being built, to catch a service that needs itself.
- `fun validate() -> array<string>` — Checks every provider without building anything: what is missing, what needs itself, and what lives longer than what it holds. The mistakes, one text each; empty when all is well. Call it once when the application starts.

# web/events.q

## `struct Events`

A set of listeners, by the type of event.

**Methods**

- `fun new() -> Events`
- `fun listen(handler: fun(E))` — Calls `handler` for every event of type `E` dispatched from now on.
- `fun dispatch(event: E) -> int` — Tells the listeners of the type of `event`. Gives back how many were called.
- `fun count() -> int` — How many listeners wait for events of type `E`.

# web/limit.q

## `fun by_header(name: string) -> fun(Request) -> string`

Counts by the value of a request header (`"unknown"` when absent).

## `fun by_path_and_header(name: string) -> fun(Request) -> string`

Counts by header and path, so that one client has a budget per route.

## `fun rate_limit(cache: Cache, limit: int, seconds: int, key_of: fun(Request) -> string) -> fun(Request, fun(Request) -> Response) -> Response`

At most `limit` requests per `seconds` for each key `key_of` gives. The answers carry
`X-RateLimit-Limit` and `X-RateLimit-Remaining`.

# web/locale.q

## `fun locale_of(req: Request) -> string`

The language chosen for this request (the default one without the middleware).

## `fun locale_middleware(tr: Translator, available: array<string>) -> fun(Request, fun(Request) -> Response) -> Response`

Chooses the language of each request among `available` (see above).

## `fun lang_for(req: Request, tr: Translator) -> Lang`

A provider for `Lang` handler parameters: add it with `Reflect.callable(locale, "lang_for")`.

## `fun use_locale(app: App, tr: Translator, available: array<string>)`

Sets everything up: the translator and the `Lang` service in the container, and the middleware.

# web/middleware.q

## `fun logging() -> fun(Request, fun(Request) -> Response) -> Response`

Writes one line in the log for each request: `GET /posts/2 -> 200 (3 ms)`, at the level `info`
(`warn` for a 4xx, `error` for a 5xx).

## `fun security_headers() -> fun(Request, fun(Request) -> Response) -> Response`

Adds the usual protective headers: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
`Referrer-Policy: same-origin`. A header the route already set is kept.

## `struct CorsOptions`

What `cors_with` allows.

**Fields**

- `origins: array<string>` — The origins that may call (`"https://app.example"`), or `"*"` for any.
- `methods: array<string>`
- `headers: array<string>` — The request headers allowed; empty means the ones the browser asks for.
- `expose: array<string>` — Response headers the page may read (`X-Request-Id`...).
- `credentials: bool` — Lets the page send cookies and credentials; then the origin is repeated, never `*`.
- `max_age: int` — Seconds a browser may keep the answer to a preflight request.

## `fun cors(origins: array<string>) -> fun(Request, fun(Request) -> Response) -> Response`

Lets browsers of these origins (`["https://app.example"]`, or `["*"]`) call the API from a
page: answers the preflight `OPTIONS` request itself and adds `Access-Control-Allow-Origin` to
the other answers.

## `fun cors_with(o: CorsOptions) -> fun(Request, fun(Request) -> Response) -> Response`

`cors` with every option: methods, headers, exposed headers, credentials, preflight cache.

## `fun bearer_token(check: fun(string) -> bool) -> fun(Request, fun(Request) -> Response) -> Response`

Refuses (`401`) the requests that do not carry `Authorization: Bearer <token>` with a token
that `check` accepts. Compare secrets with `Crypto.equal` inside `check`. The token is put in
`req.attrs["token"]` for the handlers.

## `fun request_id() -> fun(Request, fun(Request) -> Response) -> Response`

Gives each request an identifier: the `X-Request-Id` it came with, or a new one. It is put in
`req.attrs["request_id"]` and in the response's `X-Request-Id`.

# web/migrate.q

## `struct Migration`

One schema change: a unique `id` (sorted, so start it with a number or a date), the statements to
apply and the statements to undo it.

**Fields**

- `id: string`
- `up: array<string>`
- `down: array<string>`

## `struct Migrator`

Applies and undoes migrations on a database.

**Fields**

- `db: Db`
- `table: string`

**Methods**

- `fun new(db: Db) -> Migrator` — A migrator that remembers in the table `schema_migrations`.
- `fun status(migrations: array<Migration>) -> Result<array<MigrationStatus>, Error>` — Which migrations are applied.
- `fun run(migrations: array<Migration>) -> Result<array<string>, Error>` — Applies the migrations that were not yet, in the order of their ids. Gives the ids it applied. It stops at the first failure.
- `fun rollback(migrations: array<Migration>, steps: int) -> Result<array<string>, Error>` — Undoes the last `steps` applied migrations, newest first. Gives the ids it undid. A migration without `down` statements is undone by forgetting it only.

## `struct MigrationStatus`

Where a migration stands.

**Fields**

- `id: string`
- `applied: bool`

# web/openapi.q

## `fun schema_of(t: TypeInfo, schemas: Schemas) -> Json`

The schema of a type; structures are put in `schemas` and referred to.

## `fun openapi(app: App, title: string, version: string) -> Json`

The OpenAPI document of the routes of `app` (those made from functions or methods).

## `fun openapi_route(app: App, path: string, title: string, version: string)`

Adds `GET path` that answers the document (written when the first request comes, so every
route is in it).

# web/query.q

## `struct Query`

A SELECT, INSERT, UPDATE or DELETE under construction.

**Methods**

- `fun table(name: string) -> Query` — A query on this table.
- `fun select(columns: array<string>) -> Query` — The columns to read (all of them by default).
- `fun where(column: string, op: string, value: T) -> Query` — Keeps the rows where `column op value`; `op` is `=`, `!=`, `<`, `<=`, `>`, `>=`, `LIKE` or `NOT LIKE`. Several calls are joined with AND.
- `fun where_in(column: string, options: array<T>) -> Query` — Keeps the rows whose `column` is one of these values.
- `fun is_null(column: string) -> Query` — Keeps the rows whose `column` is `NULL` (`is_null`) or is not (`not_null`).
- `fun not_null(column: string) -> Query`
- `fun order_by(column: string, direction: string) -> Query` — Sorts by a column, `"asc"` or `"desc"`.
- `fun limit(n: int) -> Query` — At most `n` rows.
- `fun offset(n: int) -> Query` — Skips the first `n` rows (with `limit`).
- `fun to_sql() -> string` — The SQL of the SELECT.
- `fun params() -> array<Json>` — The values that go with the `?` of the SQL, in order.
- `fun all(db: Db) -> Result<array<map<string, Json>>, Error>` — The rows, each as a map from column to value.
- `fun first(db: Db) -> Result<map<string, Json>?, Error>` — The first row, or `none`.
- `fun count(db: Db) -> Result<int, Error>` — How many rows match.
- `fun all_as(db: Db) -> Result<array<T>, Error>` — The rows read as values of the type `T` (a structure with a field for each column; see `Json.to`).
- `fun first_as(db: Db) -> Result<T?, Error>` — The first row read as a `T`, or `none`.
- `fun insert(db: Db, row: map<string, Json>) -> Result<int, Error>` — Inserts a row: its columns and values. Gives the number of rows inserted.
- `fun insert_value(db: Db, value: T) -> Result<int, Error>` — Inserts a structure: a column for each public field.
- `fun update(db: Db, changes: map<string, Json>) -> Result<int, Error>` — Changes the columns of the rows that match. Gives the number of rows changed.
- `fun delete(db: Db) -> Result<int, Error>` — Deletes the rows that match. Gives the number of rows deleted.

# web/session.q

## `struct Session`

The data of one visitor.

**Fields**

- `data: map<string, string>`
- `changed: bool`
- `fresh: bool`

**Methods**

- `fun get(key: string) -> string?` — A value, or `none`.
- `fun set(key: string, value: string)` — Remembers a value.
- `fun remove(key: string)` — Forgets a value.
- `fun clear()` — Forgets everything (log out).
- `fun flash_set(message: string)` — A message for the next request only (`"Saved"` after a form): read it with `flash`.
- `fun flash() -> string?` — The message left by the previous request, and forgets it.
- `fun csrf_token() -> string` — The token that pages must send back with a form (made the first time).

## `fun session_of(req: Request) -> Session`

The session of this request (`sessions` middleware must be in use).

## `fun sessions(secret: string) -> fun(Request, fun(Request) -> Response) -> Response`

Loads the session from the cookie `qs` (signed with `secret`) and writes it back when it
changed. The cookie is `HttpOnly` and `SameSite=Lax`; give `secure: true` behind HTTPS.

## `fun sessions_with(secret: string, secure: bool) -> fun(Request, fun(Request) -> Response) -> Response`

Like `sessions`, with the `Secure` attribute of the cookie as you choose it.

## `fun csrf_protect() -> fun(Request, fun(Request) -> Response) -> Response`

Refuses the unsafe requests that do not carry the token of the session.

# web/testing.q

## `struct Reply`

What the application answered.

**Fields**

- `status: int`
- `headers: map<string, string>`
- `body: string`
- `cookies: array<Cookie>`

**Methods**

- `fun json() -> Result<T, Error>` — The body read as a `T`.
- `fun header(name: string) -> string?` — The value of a header (the name is compared in lower case), or `none`.
- `fun expect_status(code: int) -> Reply` — Fails the test, with the body, unless the status is `code`. Gives the reply back.
- `fun expect_body_contains(text: string) -> Reply` — Fails the test unless the body contains `text`. Gives the reply back.

## `struct Client`

Sends requests to an application.

**Fields**

- `headers: map<string, string>`
- `cookies: map<string, string>`

**Methods**

- `fun new(app: App) -> Client`
- `fun header(name: string, value: string)` — A header sent with every request from now on.
- `fun bearer(token: string)` — Sends `Authorization: Bearer token` with every request from now on.
- `fun forget_cookies()` — Forgets the cookies.
- `fun get(path: string) -> Reply`
- `fun delete(path: string) -> Reply`
- `fun post(path: string, body: string) -> Reply`
- `fun put(path: string, body: string) -> Reply`
- `fun patch(path: string, body: string) -> Reply`
- `fun post_json(path: string, value: T) -> Reply` — `POST` with `value` as a JSON body.
- `fun put_json(path: string, value: T) -> Reply`
- `fun send_json(method: string, path: string, value: T) -> Reply`
- `fun send(method: string, path: string, body: string?) -> Reply` — Sends a request. A query string in `path` is read as the server would.

# web/validate.q

## `struct NotBlank`

The field must have a value (not `none`) and, for a text, not be empty or only spaces.

## `struct Required`

The field must not be `none`.

## `struct Min`

The smallest number allowed.

## `struct Max`

The biggest number allowed.

## `struct Length`

The number of characters of a text, or of elements of an array: at least `min`, at most
`max` (`-1`: no limit).

## `struct Email`

The text must look like an email address (`name@domain.tld`).

## `struct Pattern`

The text must match this regular expression (the whole text).

## `struct OneOf`

The value must be one of these (compared as text).

## `struct Valid`

Check the structure, or each structure of the array, that the field holds.

## `struct FieldError`

One thing wrong: the field (`address.city`, `tags[2]`) and what is wrong with it.

**Fields**

- `field: string`
- `message: string`

## `struct Validator`

Checks values against the rules written on their fields.

**Methods**

- `fun new() -> Validator` — A validator with the built-in rules.
- `fun rule(name: string, check: fun(AnnotationInfo, Any) -> string?)` — Adds a rule called like an annotation of yours (`#[Slug]`). `check` gives the message that says what is wrong with the value, or `none` if it is fine.
- `fun check(value: Any) -> array<FieldError>` — Everything wrong with `value`, a structure held by an `Any`.
- `fun is_valid(value: Any) -> bool` — Whether `value` has no error.


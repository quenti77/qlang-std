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

## `fun to_response(a: Any) -> Response`

What a handler returned, as a response.

## `struct App`

The application.

**Fields**

- `container: Container`

**Methods**

- `fun new(providers: array<Callable>) -> App` — An application whose services come from these provider functions. Functions that carry a route annotation are handlers, not providers, and are left out.
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
- `fun validate() -> array<string>` — Every mistake of wiring, as texts (empty when all is well): handlers that cannot be built, services that are missing or in a cycle, routes hidden by an earlier one. Call it when the application starts.
- `fun handle(req: Request) -> Response` — The response to a request: the middleware, then the route that takes it.

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

# web/middleware.q

## `fun logging() -> fun(Request, fun(Request) -> Response) -> Response`

Writes one line in the log for each request: `GET /posts/2 -> 200 (3 ms)`, at the level `info`
(`warn` for a 4xx, `error` for a 5xx).

## `fun security_headers() -> fun(Request, fun(Request) -> Response) -> Response`

Adds the usual protective headers: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
`Referrer-Policy: same-origin`. A header the route already set is kept.

## `fun cors(origins: array<string>) -> fun(Request, fun(Request) -> Response) -> Response`

Lets browsers of these origins (`["https://app.example"]`, or `["*"]`) call the API from a
page: answers the preflight `OPTIONS` request itself and adds `Access-Control-Allow-Origin` to
the other answers.

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


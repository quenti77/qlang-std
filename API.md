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

# jwt.q

## `struct Key`

A key, for signing or for checking.

**Fields**

- `alg: string` — `HS256`, `HS384`, `HS512`, `RS256`, `RS384`, `RS512`, `PS256`, `PS384`, `PS512`, `ES256`, `ES384` or `EdDSA` (the HS384, HS512 and PS ones need `qlang` 0.55 or later).
- `key: string` — The secret, or a PEM, or a JWK (JSON text).
- `kid: string?` — The name that the token header carries, to tell the keys of a set apart.

**Methods**

- `fun hs256(secret: string) -> Key`
- `fun hs384(secret: string) -> Key` — HMAC with SHA-384: a secret of at least 48 characters.
- `fun hs512(secret: string) -> Key` — HMAC with SHA-512: a secret of at least 64 characters.
- `fun rs256(pem: string) -> Key`
- `fun rs384(pem: string) -> Key`
- `fun rs512(pem: string) -> Key`
- `fun ps256(pem: string) -> Key` — RSA-PSS with SHA-256 (the padding that is recommended over RS256).
- `fun ps384(pem: string) -> Key`
- `fun ps512(pem: string) -> Key`
- `fun es256(pem: string) -> Key`
- `fun es384(pem: string) -> Key`
- `fun eddsa(pem: string) -> Key`
- `fun named(kid: string) -> Key` — The same key under a name (`kid`).

## `struct Options`

What to check besides the signature.

**Fields**

- `issuer: string?` — The `iss` the token must carry, or `none`.
- `audience: string?` — The `aud` the token must carry (alone or in a list), or `none`.
- `leeway: int` — Seconds of difference between two clocks that are accepted for `exp` and `nbf`.
- `require_exp: bool` — A token without `exp` is refused.
- `now: int` — The time in seconds; `0` is the clock (tests give theirs).

**Methods**

- `fun new() -> Options`

## `struct Token`

A token that passed every check.

**Fields**

- `alg: string`
- `header: Json`
- `payload: Json`

**Methods**

- `fun claims() -> Result<T, Error>` — The claims read as a structure of yours (the fields you do not name are ignored).
- `fun get(name: string) -> Json?` — A claim, or `none`.
- `fun subject() -> string?` — `sub`, or `none`.
- `fun scopes() -> array<string>` — The permissions of the token: the words of a `scope` text (`"read write"`), or the texts of an `scopes` or `permissions` list.

## `fun sign_json(payload: Json, key: Key) -> Result<string, Error>`

Signs a payload (a `Json` object) and gives the token.

## `fun sign(payload: T, key: Key) -> Result<string, Error>`

Signs a structure (its public fields are the claims: `sub`, `exp`, `scope`...) and gives the token.

## `fun error_kind(e: Error) -> string`

Why a check failed: `malformed`, `algorithm`, `key`, `signature`, `expired`, `not_yet_valid`, `claims`.

## `fun verify(token: string, keys: array<Key>, opts: Options) -> Result<Token, Error>`

Checks a token against the keys and the options, and gives what it says.

## `fun keys_from_jwks(text: string) -> Result<array<Key>, Error>`

The keys of a JWKS document (`{"keys": [...]}`), as an identity provider publishes it. The algorithm is
the `alg` of each key, or `RS256`, `ES256`/`ES384`, `EdDSA` from its type. Keys that are not for signatures
are left out.

# mail.q

## `struct Mail`

An email. `text` and `html` are two versions of the body: give at least one.

**Fields**

- `sender: string` — `Name <address>` or `address`.
- `to: array<string>`
- `subject: string`
- `text: string`
- `html: string`
- `cc: array<string>`
- `bcc: array<string>`
- `reply_to: string`

## `trait Mailer`

Where a mail goes.

## `fun check(mail: Mail) -> string?`

Why the mail cannot be sent, or `none`.

## `struct MemoryMailer`

Keeps the mails in memory: for tests.

**Fields**

- `sent: array<Mail>`

**Methods**

- `fun new() -> MemoryMailer`
- `fun send(mail: Mail) -> Result<bool, Error>`

## `struct LogMailer`

Writes the mails in the log instead of sending them: for development.

**Methods**

- `fun send(mail: Mail) -> Result<bool, Error>`

## `struct ResendMailer`

[Resend](https://resend.com).

**Fields**

- `key: string`
- `base: string`
- `transport: fun(Request) -> Result<Response, Error>`

**Methods**

- `fun new(key: string) -> ResendMailer`
- `fun send(mail: Mail) -> Result<bool, Error>`

## `struct PostmarkMailer`

[Postmark](https://postmarkapp.com).

**Fields**

- `token: string`
- `base: string`
- `transport: fun(Request) -> Result<Response, Error>`

**Methods**

- `fun new(token: string) -> PostmarkMailer`
- `fun send(mail: Mail) -> Result<bool, Error>`

## `struct SendgridMailer`

[SendGrid](https://sendgrid.com).

**Fields**

- `key: string`
- `base: string`
- `transport: fun(Request) -> Result<Response, Error>`

**Methods**

- `fun new(key: string) -> SendgridMailer`
- `fun send(mail: Mail) -> Result<bool, Error>`

## `struct MailgunMailer`

[Mailgun](https://www.mailgun.com); `base` is `https://api.eu.mailgun.net` for the European region.

**Fields**

- `key: string`
- `domain: string`
- `base: string`
- `transport: fun(Request) -> Result<Response, Error>`

**Methods**

- `fun new(key: string, domain: string) -> MailgunMailer`
- `fun send(mail: Mail) -> Result<bool, Error>`

## `struct SendMail`

A job that sends a mail: `queue.push(SendMail { mail: m })`, with `handle_sends(queue, mailer)` in the worker.

**Fields**

- `mail: Mail`

## `fun handle_sends(queue: Queue, mailer: Mailer)`

Teaches `queue` to do the `SendMail` jobs with `mailer` (a refused mail is tried again like any job).

# notify.q

## `struct Notification`

What is told.

**Fields**

- `kind: string` — A short name for the sort of event (`invoice`, `comment`): the inbox keeps it.
- `title: string`
- `body: string`
- `url: string` — A page to open, if any.

## `trait Channel`

A place where notifications go.

## `struct MailChannel`

Sends an email (`to` is the address).

**Fields**

- `mailer: Mailer`
- `sender: string`

**Methods**

- `fun deliver(to: string, n: Notification) -> Result<bool, Error>`

## `struct WebhookChannel`

Posts to a chat webhook.

**Fields**

- `url: string`
- `format: string` — `slack` (`{"text": ...}`), `discord` (`{"content": ...}`) or `json` (the notification itself).
- `transport: fun(Request) -> Result<Response, Error>`

**Methods**

- `fun slack(url: string) -> WebhookChannel`
- `fun discord(url: string) -> WebhookChannel`
- `fun json(url: string) -> WebhookChannel`
- `fun deliver(to: string, n: Notification) -> Result<bool, Error>`

## `struct InboxItem`

One line of the inbox.

**Fields**

- `id: int`
- `user_id: string`
- `kind: string`
- `title: string`
- `body: string`
- `url: string`
- `created_at: int`
- `read_at: int?`

## `struct InboxChannel`

The in-app inbox of each user, in a table.

**Fields**

- `db: Db`
- `dialect: string`
- `table: string`
- `clock: fun() -> int` — The time in milliseconds; tests give their own.

**Methods**

- `fun new(db: Db, dialect: string) -> InboxChannel`
- `fun install() -> Result<bool, Error>`
- `fun list(user: string, limit: int) -> Result<array<InboxItem>, Error>` — The newest notifications of a user (`limit` of them).
- `fun unread_count(user: string) -> Result<int, Error>`
- `fun mark_read(user: string, id: int) -> Result<bool, Error>` — Marks one notification of the user as read (a user cannot mark another's).
- `fun mark_all_read(user: string) -> Result<int, Error>`
- `fun deliver(to: string, n: Notification) -> Result<bool, Error>`

## `struct Notifier`

The channels of the application, by name.

**Fields**

- `channels: map<string, Channel>`

**Methods**

- `fun new() -> Notifier`
- `fun channel(name: string, c: Channel)`
- `fun send(names: array<string>, to: string, n: Notification) -> array<string>` — Sends on each named channel. Gives the errors, one per channel that failed (an empty list: all went well). An unknown channel name is an error too.

# queue.q

## `struct JobRow`

A job the queue holds. `id` and `token` belong to the driver.

**Fields**

- `id: string`
- `kind: string`
- `payload: string`
- `attempts: int`
- `token: string`

## `struct FailedJob`

A job that gave up.

**Fields**

- `id: string`
- `kind: string`
- `payload: string`
- `attempts: int`
- `error: string`
- `queue: string` — The queue it came from (`"default"` unless you added others with `Queue.lane`).

## `trait QueueDriver`

Where the jobs are kept: what a `Queue` needs from the database or from Redis. Times are in
milliseconds.

## `struct DbDriver`

The jobs in a SQL database.

**Fields**

- `db: Db`
- `dialect: string`
- `table: string` — The name of the table of waiting jobs; the failed ones are in `{table}_failed`.

**Methods**

- `fun install() -> Result<bool, Error>`
- `fun push(kind: string, payload: string, available_at: int, now: int) -> Result<bool, Error>`
- `fun waits() -> bool`
- `fun claim(now: int, timeout: int, wait: int) -> Result<JobRow?, Error>`
- `fun done(job: JobRow) -> Result<bool, Error>`
- `fun release(job: JobRow, available_at: int, why: string) -> Result<bool, Error>`
- `fun fail(job: JobRow, why: string, now: int) -> Result<bool, Error>`
- `fun requeue(job: JobRow, available_at: int) -> Result<bool, Error>`
- `fun lock(key: string, seconds: int, now: int) -> Result<bool, Error>`
- `fun unlock(key: string) -> Result<bool, Error>`
- `fun pending() -> Result<int, Error>`
- `fun failed() -> Result<array<FailedJob>, Error>`
- `fun retry_failed(id: string, now: int) -> Result<bool, Error>`
- `fun forget_failed(id: string) -> Result<bool, Error>`
- `fun countdown_start(key: string, n: int, seconds: int, now: int) -> Result<bool, Error>`
- `fun countdown(key: string) -> Result<bool, Error>`

## `struct RedisDriver`

The jobs in Redis, like Laravel's Redis queue: the ready jobs are a list, the delayed ones and the
running ones sorted sets (by the time they are due, by the time their reservation ends), and a worker
with nothing to do waits on a list that every push writes to, so a new job is picked up at once.

**Fields**

- `redis: Redis`
- `name: string` — The name of the queue; the keys are `queues:{name}`, `queues:{name}:delayed`...

**Methods**

- `fun install() -> Result<bool, Error>`
- `fun waits() -> bool`
- `fun push(kind: string, payload: string, available_at: int, now: int) -> Result<bool, Error>`
- `fun claim(now: int, timeout: int, wait: int) -> Result<JobRow?, Error>`
- `fun done(job: JobRow) -> Result<bool, Error>`
- `fun release(job: JobRow, available_at: int, why: string) -> Result<bool, Error>`
- `fun fail(job: JobRow, why: string, now: int) -> Result<bool, Error>`
- `fun requeue(job: JobRow, available_at: int) -> Result<bool, Error>`
- `fun lock(key: string, seconds: int, now: int) -> Result<bool, Error>`
- `fun unlock(key: string) -> Result<bool, Error>`
- `fun pending() -> Result<int, Error>`
- `fun failed() -> Result<array<FailedJob>, Error>`
- `fun retry_failed(id: string, now: int) -> Result<bool, Error>`
- `fun forget_failed(id: string) -> Result<bool, Error>`
- `fun countdown_start(key: string, n: int, seconds: int, now: int) -> Result<bool, Error>`
- `fun countdown(key: string) -> Result<bool, Error>`

## `struct Outcome`

What a job does for the queue: `done`, `failed` (it will be tried again, or abandoned after the last
attempt) or `released` (it waits, and the attempt is **not** counted: a middleware that says "not now").

**Fields**

- `status: string`
- `why: string`
- `delay: int`

**Methods**

- `fun done() -> Outcome`
- `fun failed(why: string) -> Outcome`
- `fun release(seconds: int) -> Outcome` — Wait `seconds`, then try again without using an attempt.

## `struct Job`

The job that a middleware sees.

**Fields**

- `id: string`
- `kind: string`
- `attempts: int`
- `payload: string`

## `struct Retry`

`#[Retry(tries: 5, backoff: [10, 60, 300])]` on a job structure: how many times it is tried (3 by
default), and the seconds to wait before attempt 2, 3...; the last number is used for the next ones.

## `struct Unique`

`#[Unique(seconds: 3600)]` on a job structure: while a job with the same fields waits or runs (at
most `seconds`), pushing it again does nothing (`push` gives `false`).

## `struct Delay`

`#[Delay(seconds: 30)]` on a job structure: it starts that long after it is pushed, unless `push_in`
says otherwise.

## `struct OnQueue`

`#[OnQueue(name: high)]` on a job structure: the queue it goes to when `push` is used (see `Queue.lane`).

## `struct Settings`

What the annotations of a job structure say.

**Fields**

- `tries: int`
- `backoff: array<int>`
- `unique: int`
- `delay: int`
- `lane: string`

## `struct WorkOptions`

What `work_with` does.

**Fields**

- `once: bool` — Stop when no job is due (instead of waiting for new ones).
- `max_jobs: int` — Stop after this many jobs (0: no limit): a worker that restarts often keeps its memory small.
- `max_seconds: int` — Stop after this many seconds (0: no limit), at the end of the job that is running.
- `sleep_ms: int` — With a database: how long to wait between two looks when nothing is due.
- `queues: array<string>` — The queues to serve, the most important first (`["high", "default"]`); none: all of them, in the order they were added.

## `struct Step`

A job written down for later: where it goes, its type and its fields (as text).

**Fields**

- `queue: string`
- `kind: string`
- `payload: string`
- `unique: int`
- `delay: int`

## `struct Queue`

The queue and its handlers.

**Fields**

- `driver: QueueDriver`
- `max_attempts: int` — Tries for a job that has no `#[Retry]`.
- `timeout: int` — Seconds after which a job that is still marked as running is given to another worker.
- `wait: int` — With Redis: seconds a worker waits for a new job before it looks again (and checks for a stop order).
- `clock: fun() -> int` — The time in milliseconds; tests give their own.

**Methods**

- `fun new(db: Db, dialect: string) -> Queue` — A queue in `db`; `dialect` is `"sqlite"`, `"postgres"` or `"mysql"` (it only changes how the tables are made).
- `fun redis(redis: Redis, name: string) -> Queue` — A queue in Redis, under the name `name` (`"default"`).
- `fun with(driver: QueueDriver) -> Queue` — A queue on a driver of your own.
- `fun install() -> Result<bool, Error>` — Makes the tables if they do not exist (checks the connection with Redis).
- `fun use(m: fun(Job, fun() -> Outcome) -> Outcome)` — Code around **every** job (see `JobMiddleware`); the first added is the outermost.
- `fun handle(handler: fun(T) -> string?)` — Says what to do with the jobs of type `T`: `none` when it is done, otherwise why it failed. The annotations of `T` (`#[Retry]`, `#[Unique]`, `#[Delay]`) say how it is tried.
- `fun handle_with(handler: fun(T) -> string?, around: array<fun(Job, fun() -> Outcome) -> Outcome>)` — Like `handle`, with middleware for this type of job only (inside the global ones).
- `fun lane(name: string, driver: QueueDriver)` — Adds a queue next to `"default"`: `queue.lane("high", DbDriver { db: db, dialect: "sqlite", table: "jobs_high" })` or `queue.lane("high", RedisDriver { redis: redis, name: "high" })`. A worker serves the queues in the order of `WorkOptions.queues`, so the jobs of an earlier one always go first.
- `fun push(job: T) -> Result<bool, Error>` — Writes a job down, to be done as soon as a worker is free (or after its `#[Delay]`), in the queue its `#[OnQueue]` names (`"default"`). Gives `false` when a `#[Unique]` job like it is already there.
- `fun push_in(job: T, seconds: int) -> Result<bool, Error>` — Writes a job down, to be done after `seconds`.
- `fun push_on(lane: string, job: T) -> Result<bool, Error>` — Writes a job down in the queue `lane`, whatever its `#[OnQueue]` says.
- `fun send(item: Step, meta: Meta?, seconds: int) -> Result<bool, Error>` — Writes a item down; `seconds` below zero: the delay of the item.
- `fun chain() -> Chain` — A chain of jobs: each starts when the one before it is done, and none starts if one gives up.
- `fun batch() -> Batch` — A batch of jobs, done in parallel; one more job can follow when all are done, one when a job gives up.
- `fun pending() -> Result<int, Error>` — How many jobs wait (or run), in every queue.
- `fun work_one() -> Result<bool, Error>` — Does the next due job. Gives `true` when there was one (done or failed), `false` when none was due.
- `fun work(once: bool) -> Result<int, Error>` — Does the due jobs. With `once`, ends when none is due; otherwise it waits for new ones. It also ends, at the end of the job that is running, when the process was told to stop (`Process.stopping()`).
- `fun work_with(o: WorkOptions) -> Result<int, Error>` — `work` with its limits: see `WorkOptions`. Gives how many jobs were done. With Redis the wait is on the queue itself, so a new job starts at once; with a database the worker looks again after `sleep_ms`. A worker that serves several queues looks at them in turn (at least every 250 ms with Redis). A database error ends it with that error.
- `fun failed() -> Result<array<FailedJob>, Error>` — The jobs that gave up, oldest first, in every queue (`queue` says which).
- `fun retry_failed(id: string) -> Result<bool, Error>` — Puts a failed job back in the queue, with a fresh count of attempts. `false` if there is none with this id (the queues are searched in order; `retry_failed_on` names one).
- `fun retry_failed_on(lane: string, id: string) -> Result<bool, Error>`
- `fun forget_failed(id: string) -> Result<bool, Error>` — Deletes a failed job. `false` if there is none with this id.

## `struct Chain`

Jobs that follow each other (`queue.chain()`).

**Fields**

- `queue: Queue`
- `steps: array<Step>`
- `fails: array<Step>`

**Methods**

- `fun add(job: T) -> Chain` — The next job of the chain.
- `fun on_failure(job: T) -> Chain` — A job to push if one of the chain gives up.
- `fun dispatch() -> Result<bool, Error>` — Pushes the first job. `false` when the chain is empty or the first job is a `#[Unique]` one already there.

## `struct Batch`

Jobs done in parallel (`queue.batch()`): `when_done` pushes a job when all are done, `when_failed` when one gives up
(once). The count is kept by the driver of the default queue, so any number of workers can finish them.

**Fields**

- `queue: Queue`
- `steps: array<Step>`
- `after: array<Step>`
- `fails: array<Step>`

**Methods**

- `fun add(job: T) -> Batch`
- `fun when_done(job: T) -> Batch` — The job to push when every job of the batch is done.
- `fun when_failed(job: T) -> Batch` — The job to push, once, if a job of the batch gives up.
- `fun dispatch() -> Result<string, Error>` — Pushes the jobs and gives the id of the batch.

## `fun rate_limited(cache: Cache, key: fun(Job) -> string, limit: int, seconds: int) -> fun(Job, fun() -> Outcome) -> Outcome`

A middleware: at most `limit` jobs of the same key (by default their type) per `seconds`; the others wait
for the next window, without using an attempt. The count is in `cache`: with Redis it is exact for every
worker.

## `fun without_overlapping(cache: Cache, key: fun(Job) -> string, expire_after: int, release_after: int) -> fun(Job, fun() -> Outcome) -> Outcome`

A middleware: two jobs with the same key never run together; the second waits `release_after` seconds,
without using an attempt. `expire_after` frees the key if a worker dies.

## `fun by_kind(job: Job) -> string`

A key: the type of the job.

## `fun by_payload(job: Job) -> string`

A key: the type and the fields of the job.

# s3.q

## `struct S3`

A bucket.

**Fields**

- `endpoint: string`
- `region: string`
- `access_key: string`
- `secret: string`
- `bucket: string`
- `transport: fun(Request) -> Result<Response, Error>`
- `clock: fun() -> int` — The time in milliseconds; tests give their own.

**Methods**

- `fun new(endpoint: string, region: string, access_key: string, secret: string, bucket: string) -> S3`
- `fun sign(method: string, key: string, body: string, extra: map<string, string>) -> map<string, string>` — The headers of a signed request (`Authorization`, `x-amz-date`, `x-amz-content-sha256`).
- `fun sign_hash(method: string, key: string, payload: string, extra: map<string, string>) -> map<string, string>` — Like `sign`, for a body whose SHA-256 (in hexadecimal) you already have.
- `fun put(key: string, body: string, content_type: string) -> Result<bool, Error>` — Writes the object (text).
- `fun put_bytes(key: string, data: bytes, content_type: string) -> Result<bool, Error>` — Writes the object from bytes (any file).
- `fun get_bytes(key: string) -> Result<bytes?, Error>` — The object as bytes, or `none` when it does not exist.
- `fun get(key: string) -> Result<string?, Error>` — The object as text, or `none` when it does not exist.
- `fun exists(key: string) -> Result<bool, Error>` — Whether the object exists.
- `fun delete(key: string) -> Result<bool, Error>` — Deletes the object (also fine when it was not there).
- `fun presign(method: string, key: string, seconds: int) -> string` — A link that lets whoever has it do `method` (`GET`, `PUT`, `DELETE`) on the object for `seconds` (at most 7 days), without any key: for a browser that uploads or downloads by itself.

# schedule.q

## `struct Cron`

A parsed cron expression.

**Fields**

- `minutes: array<int>`
- `hours: array<int>`
- `days: array<int>`
- `months: array<int>`
- `weekdays: array<int>`
- `any_day: bool`
- `any_weekday: bool`

**Methods**

- `fun parse(text: string) -> Result<Cron, Error>` — Reads `"m h dom mon dow"`.
- `fun matches(at: datetime) -> bool` — Whether the expression matches this minute.

## `struct Task`

One task of the schedule.

**Fields**

- `name: string`
- `cron: Cron`
- `run: fun() -> string?`

## `struct Schedule`

A list of tasks.

**Fields**

- `cache: Cache`
- `tasks: array<Task>`
- `clock: fun() -> int` — The time in milliseconds; tests give their own.

**Methods**

- `fun new(cache: Cache) -> Schedule` — `cache` is where machines agree on who runs a minute.
- `fun cron(name: string, expression: string, run: fun() -> string?)` — A task on a cron expression. Panics if the expression is wrong (it is a mistake in the program, found at start).
- `fun every_minutes(name: string, n: int, run: fun() -> string?)` — A task every `n` minutes (1 to 59), or every `n/60` hours when `n` is a multiple of 60 up to a day.
- `fun daily_at(name: string, hour: int, minute: int, run: fun() -> string?)` — A task every day at `hour`:`minute` UTC.
- `fun run_due() -> int` — Runs the tasks that are due this minute and that nobody ran yet. Gives how many ran. Call it at least once a minute (`work` does).
- `fun work()` — Looks at the clock every second and runs what is due, until the process is told to stop.

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

## `struct Guard`

`#[Guard("auth")]` on a route or on a controller: the guard of that name (`App.guard`) runs
before the handler, and may answer instead (`401`, a redirect...). Several can be stacked.

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
- `guards: array<string>` — The names of the guards that run before it.

## `fun to_response(a: Any) -> Response`

What a handler returned, as a response.

## `struct App`

The application.

**Fields**

- `container: Container`

**Methods**

- `fun new(providers: array<Callable>) -> App` — An application whose services come from these provider functions. Functions that carry a route annotation are handlers, not providers, and are left out.
- `fun services(constructors: array<Callable>)` — Provides every structure marked `#[di.Service]` among these constructors (`Reflect.constructors(models)`): its fields are what it needs.
- `fun bind()` — Says that whoever needs an `I` (a trait) gets the service `T`.
- `fun guard(name: string, check: fun(Request) -> Response?)` — Names a guard for `#[Guard("name")]`. It receives the request (put what it learns in `req.attrs`) and gives `none` to let it through or a response to stop there.
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

# web/auth.q

## `fun jwt_guard(keys: array<Key>, options: Options) -> fun(Request) -> Response?`

Lets through the requests with a valid token: its signature and its dates are checked with `keys` and
`options`. The token is kept for the route (`token_of`, `claims_of`).

## `fun token_of(req: Request) -> Token?`

The token a `jwt_guard` accepted for this request.

## `fun claims_of(req: Request) -> T?`

The claims of that token, read as a structure of yours.

## `fun scope_guard(required: array<string>) -> fun(Request) -> Response?`

Lets through the tokens that have **all** of these permissions (`scope: "read write"`, or a list in
`scopes` or `permissions`); the others get `403`. Put it after `jwt_guard`.

## `fun fetch_jwks(url: string, cache: Cache, ttl: int) -> Result<array<Key>, Error>`

The keys of the JWKS published at `url`, kept `ttl` seconds in the cache.

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
- `fun incr(key: string, ttl: int) -> int`

## `struct FileStore`

A store with a file per key in `dir`, which must exist. The first line of a file is the
moment (milliseconds) its entry expires.

**Methods**

- `fun new(dir: string) -> FileStore`
- `fun read(key: string) -> string?`
- `fun write(key: string, value: string, ttl: int)`
- `fun drop(key: string)`
- `fun incr(key: string, ttl: int) -> int`

## `struct RedisStore`

A store in Redis, shared by every worker of every machine. `prefix` is put before each key.

**Fields**

- `redis: Redis`
- `prefix: string`

**Methods**

- `fun new(redis: Redis, prefix: string) -> RedisStore`
- `fun read(key: string) -> string?`
- `fun write(key: string, value: string, ttl: int)`
- `fun drop(key: string)`
- `fun incr(key: string, ttl: int) -> int`

## `struct Cache`

A cache over a store.

**Methods**

- `fun new(store: Store) -> Cache`
- `fun memory() -> Cache` — A cache in the memory of the worker.
- `fun redis(redis: Redis, prefix: string) -> Cache` — A cache in Redis (shared by every worker of every machine); keys start with `prefix`.
- `fun increment(key: string, ttl: int) -> int` — Adds 1 to a counter and gives the new value; a new counter lives `ttl` seconds. Atomic in Redis, so a limit shared by several workers stays exact.
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

## `struct Service`

Marks a structure as a service: the container builds it from its fields (see
`Container.services`). `#[Scoped]` and `#[Transient]` go next to it.

## `fun services_of(constructors: array<Callable>) -> array<Callable>`

The constructors (`Reflect.constructors(module)`) of the structures marked `#[Service]`: add
them to the providers of something that takes a list (`Cli.new(Reflect.callables(providers)
.concat(services_of(Reflect.constructors(providers))))`).

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
- `maker: Callable?`
- `alias: string` — When not empty: this service is the one called `alias` (see `bind`).

## `struct Container`

Services, built from providers.

**Methods**

- `fun new(callables: array<Callable>) -> Container` — A container whose providers are the given functions (`Reflect.callables(module)`).
- `fun provide(c: Callable)` — Adds a provider function (`Reflect.callable("name")`).
- `fun services(constructors: array<Callable>)` — Provides every structure marked `#[Service]` among the constructors (`Reflect.constructors(module)`): its fields are its dependencies.
- `fun bind()` — Says that the service `I` (usually a trait) is the service `T`: whoever needs an `I` gets the `T`. Tests bind the same `I` to another one.
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

# web/health.q

## `struct Health`

The checks of the application.

**Fields**

- `checks: array<(string, fun() -> string?)>`

**Methods**

- `fun new() -> Health`
- `fun check(name: string, run: fun() -> string?)`
- `fun ready() -> (int, string)` — Runs the checks. Gives the status code and the JSON body.
- `fun mount(app: App, path: string)` — Adds `path/live` and `path/ready`.

## `fun db_check(db: Db) -> fun() -> string?`

A check that runs `SELECT 1` on the database.

## `fun redis_check(redis: Redis) -> fun() -> string?`

A check that sends `PING` to Redis.

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

# web/metrics.q

## `struct Metrics`

Request counters kept in a cache.

**Fields**

- `cache: Cache`
- `routes: array<string>`
- `methods: array<string>`
- `buckets: array<int>` — Upper limits of the duration buckets, in milliseconds.
- `queue: Queue?`

**Methods**

- `fun new(cache: Cache, app: App) -> Metrics` — Counters for the routes of `app` (read now).
- `fun with_queue(queue: Queue) -> Metrics` — Adds the size of the job queue to the page.
- `fun middleware() -> fun(Request, fun(Request) -> Response) -> Response` — Counts every request and its duration. Put it first (`app.use`) to also count what other middleware refuses.
- `fun render() -> string` — The page in the Prometheus text format.
- `fun mount(app: App, path: string, guard: fun(Request) -> Response?)` — Adds `GET path` that serves the page, behind `guard` (give one: metrics tell attackers how your site is used).

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

# web/queue_admin.q

## `fun mount(app: App, queue: Queue, path: string, guard: fun(Request) -> Response?)`

Adds the dashboard routes under `path`; `guard` runs first on each of them (`none`: let through).

# web/refresh.q

## `struct Refresh`

A refresh token store in a SQL database.

**Fields**

- `db: Db`
- `ttl: int` — Seconds a token lives (30 days by default).
- `table: string` — The table.
- `clock: fun() -> int` — The time in milliseconds; tests give their own.

**Methods**

- `fun new(db: Db) -> Refresh`
- `fun install() -> Result<bool, Error>` — Makes the table if it does not exist.
- `fun issue(user: string) -> Result<string, Error>` — A new token for `user`, starting a new family (one login).
- `fun rotate(token: string) -> Result<Rotated, Error>` — Burns `token` and gives its successor. If `token` was already used, every token of its family is revoked and the error starts with `reused`.
- `fun revoke(token: string) -> Result<bool, Error>` — Revokes this token's whole session (a "sign out"). `false` if the token is unknown.
- `fun revoke_user(user: string) -> Result<int, Error>` — Revokes every session of `user`. Gives how many tokens were deleted.
- `fun purge() -> Result<int, Error>` — Deletes the tokens that have expired (run it now and then).

## `struct Rotated`

The token to send, and the user it belongs to.

**Fields**

- `user: string`
- `token: string`

# web/relations.q

## `struct With`

A row and what relates to it.

**Fields**

- `item: P`
- `related: R`

## `fun has_many(db: Db, parents: array<P>, key: string, table: string, foreign_key: string) -> Result<array<With<P, array<C>>>, Error>`

The `C` rows whose `foreign_key` is the `key` of each parent.

## `fun has_many_where(db: Db, parents: array<P>, key: string, table: string, foreign_key: string, constrain: fun(Query) -> Query) -> Result<array<With<P, array<C>>>, Error>`

`has_many` with a function that adds conditions or an order to the query of the children.

## `fun has_one(db: Db, parents: array<P>, key: string, table: string, foreign_key: string) -> Result<array<With<P, C?>>, Error>`

The first `C` row whose `foreign_key` is the `key` of each parent.

## `fun belongs_to(db: Db, children: array<C>, foreign_key: string, table: string, key: string) -> Result<array<With<C, O?>>, Error>`

The `O` row each child points to: the one whose `key` is the child's `foreign_key`.

## `fun belongs_to_many(db: Db, parents: array<P>, key: string, pivot: string, parent_key: string, related_key: string, table: string, id: string) -> Result<array<With<P, array<R>>>, Error>`

Many-to-many through a table: `pivot` has a `parent_key` column (the `key` of the parent) and a
`related_key` column (the `id` of the related row in `table`).

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
- `fun post_form(path: string, fields: map<string, string>) -> Reply` — `POST` of an HTML form: the fields as `application/x-www-form-urlencoded`.
- `fun post_json(path: string, value: T) -> Reply` — `POST` with `value` as a JSON body.
- `fun put_json(path: string, value: T) -> Reply`
- `fun send_json(method: string, path: string, value: T) -> Reply`
- `fun send(method: string, path: string, body: string?) -> Reply` — Sends a request. A query string in `path` is read as the server would.
- `fun request(method: string, path: string, body: string?) -> Request` — The request this client would send (its headers and cookies included), without sending it.

## `struct WsClient`

A WebSocket opened on an application without a network: what the server does is done here, one
event at a time. The callbacks run in the test, so what they write is read with `received`.

```
let a = WsClient.open(app, "/chat?name=ada")
a.received()              -- ["welcome ada"]
a.send("hi")
a.received()              -- what the handler answered
```

**Fields**

- `conn: WebSocket`

**Methods**

- `fun open(app: App, path: string) -> WsClient` — Opens the WebSocket of `path`; stops the test if the route does not answer with one.
- `fun try_open(app: App, path: string, headers: map<string, string>) -> Result<WsClient, Error>` — Like `open`, with extra headers (`origin`, `authorization`); `err` says why it did not open (the status the route answered with, for example).
- `fun send(text: string)` — The client sends a text message.
- `fun send_bytes(data: bytes)` — The client sends a binary message.
- `fun tick()` — The time for `on_tick` came.
- `fun received() -> array<string>` — The texts the server sent since the last call.
- `fun frames() -> array<WsFrame>` — Every frame the server sent since the last call (texts, binaries, a close).
- `fun close()` — The client leaves: `on_close` runs.
- `fun is_open() -> bool` — Whether the connection is still open (the server may have closed it).

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

# web/ws.q

## `struct Hub`

The connections of one worker, in rooms.

**Fields**

- `rooms: map<string, array<WebSocket>>`

**Methods**

- `fun new() -> Hub`
- `fun join(room: string, conn: WebSocket)` — Puts the connection in a room.
- `fun leave(conn: WebSocket)` — Takes the connection out of every room. Call it in `on_close`.
- `fun count(room: string) -> int` — How many connections are in the room.
- `fun broadcast(room: string, text: string, except: string?) -> int` — Sends a text to everybody in the room except `except` (a connection id, or `none`). Gives how many received it.

## `struct Bus`

Messages shared by every worker through a table.

**Fields**

- `db: Db`
- `table: string`
- `dialect: string`
- `clock: fun() -> int` — The time in milliseconds; tests give their own.
- `numbered: bool` — Send each message as `{"room": ..., "id": 12, "text": ...}` so a client can say where it stopped (see `replay`). Off by default: the message is sent as it was published.

**Methods**

- `fun new(db: Db, dialect: string) -> Bus` — A bus on `db`; `dialect` is `"sqlite"`, `"postgres"` or `"mysql"`.
- `fun install() -> Result<bool, Error>` — Makes the table if it does not exist.
- `fun publish(room: string, text: string) -> Result<bool, Error>` — Writes a message for the room.
- `fun last(room: string) -> int` — The number of the last message of the room (0 if none): where a new connection starts, so that it only hears what comes after.
- `fun since(room: string, after: int) -> array<(int, string)>` — The messages of the room after number `after`, oldest first, as (number, text).
- `fun frame(room: string, id: int, text: string) -> string` — What is sent for message number `id`: the text itself, or with `numbered` its number too.
- `fun replay(conn: WebSocket, room: string, after: int) -> int` — For a client that reconnects: sends the messages published in the room after number `after` (the last one it saw; the client keeps it, so use `numbered`), oldest first, and makes `deliver` go on from there. Gives how many were sent. Messages that were pruned are gone: `replay` is for short gaps, and a client that was away for long should reload its page of history. A message may come twice when `Relay` and `replay` meet: the client ignores a number it already has.
- `fun deliver(conn: WebSocket, room: string)` — Sends to the connection what was published in the room since the last time it was asked (`conn.data["cursor:room"]` remembers where it stopped). Call it from `on_tick`.
- `fun prune(seconds: int) -> Result<int, Error>` — Deletes the messages older than `seconds`. Run it from time to time.

## `trait Feed`

Where a `Relay` takes the messages from: the database (`DbFeed`) or Redis (`RedisFeed`).

## `struct DbFeed`

The messages of a `Bus` (the database), read after the last one seen in each room.

**Fields**

- `bus: Bus`

**Methods**

- `fun new(bus: Bus) -> DbFeed`
- `fun watch(room: string)`
- `fun pull(active: array<string>) -> array<(string, string)>`

## `struct RedisFeed`

The messages of Redis channels (`ws:{room}`): the worker subscribes once per room, Redis pushes the
messages, and `pull` only reads what already arrived: no query at all while nothing is said.

**Fields**

- `sub: Subscription`
- `prefix: string`

**Methods**

- `fun open(url: string, prefix: string) -> Result<RedisFeed, Error>` — Opens the connection that listens. Channels are named `{prefix}{room}`.
- `fun watch(room: string)`
- `fun pull(active: array<string>) -> array<(string, string)>`

## `struct RedisBus`

Publishes to the Redis channels a `RedisFeed` listens to.

**Fields**

- `redis: Redis`
- `prefix: string`

**Methods**

- `fun new(redis: Redis, prefix: string) -> RedisBus`
- `fun publish(room: string, text: string) -> Result<int, Error>` — Sends a text to the room, on every worker of every machine. Gives how many workers listen.

## `struct Relay`

Brings what a feed holds to the connections of **this worker**, with one read per room and
interval whatever the number of connections (none at all with Redis, which pushes): the read is
shared, the fan-out is in memory (through a `Hub`). Make one per worker, next to the hub.

```
let hub = ws.Hub.new()
let relay = ws.Relay.new(bus, hub, 250)                   -- a bus in the database
-- or: let relay = ws.Relay.with_feed(redis_feed, hub, 50)   -- Redis
-- in the handler:
on_open: fun(c: WebSocket)
  hub.join("lobby", c)
  relay.watch("lobby")
end,
on_tick: fun(c: WebSocket) relay.pump() end,
```

Every connection may call `pump` from its tick: the call returns at once unless the interval has
passed since the last read. A worker with 1 000 connections still makes `1000 / interval` cheap calls
and one read per room each `interval`, instead of one query per connection.

**Fields**

- `feed: Feed`
- `hub: Hub`
- `interval: int`
- `clock: fun() -> int` — The time in milliseconds; tests give their own.

**Methods**

- `fun new(bus: Bus, hub: Hub, interval: int) -> Relay` — A relay on the bus in the database; `interval` is the number of milliseconds between two reads.
- `fun with_feed(feed: Feed, hub: Hub, interval: int) -> Relay`
- `fun watch(room: string)` — Starts listening to a room.
- `fun pump() -> int` — Reads the new messages (if the interval passed) and sends them to the members of the hub. Gives how many messages were read.

## `fun origin_guard(allowed: array<string>) -> fun(Request) -> Response?`

A guard that only lets through the requests whose `Origin` is one of these (or that have none,
which is the case of programs that are not browsers). Register it with `app.guard("origin", ...)`
and put `#[web.Guard("origin")]` on the WebSocket route.


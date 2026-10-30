--" # Accounts: register, sign in, forgotten password, email check

The whole path of a user, ready to mount: **registration**, **sign in** and **sign out** (with the cookie
session of `session.q`), **forgotten password** by email, **email verification**, and the guards that
protect a route.

```
let db = Db.connect("sqlite://app.db").unwrap()
let accounts = Accounts.new(db, "sqlite", ResendMailer.new(env.get("RESEND_KEY") ?? ""), Options {
  base_url: "https://app.example.org",
  sender: "App <noreply@example.org>",
})
accounts.install().unwrap()                         -- the tables, once

app.use(sessions(secret))                           -- accounts need the session middleware
mount(app, accounts, "/auth")
app.guard("login", require_login())
```

`mount` adds these JSON routes (a form body works too):

| Route | Body | Answer |
| --- | --- | --- |
| `POST /auth/register` | `email`, `password` | `201` and the account; a verification email is sent |
| `POST /auth/login` | `email`, `password` | `200` and the account; the session is renewed |
| `POST /auth/logout` | | `200` |
| `GET /auth/me` | | the signed in account, or `401` |
| `POST /auth/password/forgot` | `email` | `202` **always**, whether the address exists or not |
| `POST /auth/password/reset` | `token`, `password` | `200` and the account |
| `POST /auth/email/verify` (or `GET ?token=`) | `token` | `200` and the account |
| `POST /auth/email/resend` | | `202`, for the signed in account |

What it takes care of: passwords are hashed with Argon2 (`Password.hash`) and re-hashed when the settings age;
a wrong email and a wrong password give the **same** answer and take about the same time; the tokens of the
emails are random, only their hash is kept, they live one hour (reset) or one day (verification) and work
once; a new password ends the other reset links of that account; signing in gives the session a new identifier.

What it does not do: limit the attempts (put `rate_limit` of `limit.q` in front of `/auth/login` and
`/auth/password/forgot`), send the email in the background (put it in the job queue if your mail service is
slow), or give a front end: the emails carry the link `base_url + reset_path + ?token=...`, your page reads
the token and posts it.
--"
import "app.q" as web
import "session.q" as sess
import "query.q" as q
import "../mail.q" as mail

--" What the module needs to know about your application. --"
struct Options
  --" The address of the site, for the links in the emails (no trailing `/`). --"
  public base_url: string = "http://localhost:8080"
  --" Who the emails come from (`Name <address>`). --"
  public sender: string = "App <noreply@example.org>"
  --" The name of the application, in the emails. --"
  public app_name: string = "the application"
  --" The page of your site that takes the token of a forgotten password. --"
  public reset_path: string = "/password/reset"
  --" The page of your site that takes the token of an email check. --"
  public verify_path: string = "/email/verify"
  --" The shortest password accepted. --"
  public min_password: int = 8
  --" Seconds a forgotten-password link lives. --"
  public reset_ttl: int = 3600
  --" Seconds an email-check link lives. --"
  public verify_ttl: int = 86400
  --" Refuse to sign in until the email is checked (`403`). --"
  public require_verified: bool = false
  --" The table of the accounts; the tokens are in `{table}_tokens`. --"
  public table: string = "accounts"
end

--" An account, as it is sent out (never the hash of the password). --"
struct Account
  public id: int
  public email: string
  public verified: bool
end

--" The service: a database, a way to send email, and the options. --"
struct Accounts
  public db: Db
  public dialect: string
  public mailer: mail.Mailer
  public options: Options
  --" The clock in milliseconds (replaced in tests). --"
  public now: fun() -> int
  dummy: array<string>
end

struct Row
  public id: int
  public email: string
  public password_hash: string
  public verified_at: int?
end

fun problem<T>(status: int, message: string) -> Result<T, web.Problem>
  Result<T, web.Problem>.Err(web.Problem { status: status, message: message })
end

fun id_column(dialect: string) -> string
  if dialect == "postgres" then
    return "BIGSERIAL PRIMARY KEY"
  end
  if dialect == "mysql" then
    return "BIGINT AUTO_INCREMENT PRIMARY KEY"
  end
  "INTEGER PRIMARY KEY AUTOINCREMENT"
end

fun number(n: int) -> Json
  Json.number(n as float)
end

fun hash_of(token: string) -> string
  Hash.sha256(token)
end

impl Accounts
  --" `dialect` is `"sqlite"`, `"postgres"` or `"mysql"` (it only matters when the tables are made). --"
  public fun new(db: Db, dialect: string, mailer: mail.Mailer, options: Options) -> Accounts
    Accounts { db: db, dialect: dialect, mailer: mailer, options: options, now: fun() -> int time.now() end, dummy: [] }
  end

  --" Makes the tables if they do not exist. --"
  public fun install(self) -> Result<bool, Error>
    let users = self.db.execute("CREATE TABLE IF NOT EXISTS {self.options.table} (id {id_column(self.dialect)}, email VARCHAR(190) NOT NULL UNIQUE, password_hash TEXT NOT NULL, verified_at BIGINT, created_at BIGINT NOT NULL)", [])
    if users.is_err() then
      return Result<bool, Error>.Err(users.unwrap_err())
    end
    let tokens = self.db.execute("CREATE TABLE IF NOT EXISTS {self.options.table}_tokens (token_hash VARCHAR(64) PRIMARY KEY, account_id BIGINT NOT NULL, kind VARCHAR(16) NOT NULL, expires_at BIGINT NOT NULL, used_at BIGINT)", [])
    if tokens.is_err() then
      return Result<bool, Error>.Err(tokens.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  fun row_of(self, where_sql: string, params: array<Json>) -> Row?
    let rows = self.db.query("SELECT id, email, password_hash, verified_at FROM {self.options.table} WHERE {where_sql}", params)
    if rows.is_err() or rows.unwrap().is_empty() then
      return none
    end
    let r = rows.unwrap()[0]
    let verified = r.get("verified_at", Json.null())
    Row {
      id: r.get("id", Json.null()).as_number() as int,
      email: r.get("email", Json.null()).as_string(),
      password_hash: r.get("password_hash", Json.null()).as_string(),
      verified_at: if verified.is_null() then none else verified.as_number() as int end,
    }
  end

  fun account_of_row(self, row: Row) -> Account
    Account { id: row.id, email: row.email, verified: row.verified_at != none }
  end

  --" The account with this id, or `none`. --"
  public fun find(self, id: int) -> Account?
    let row = self.row_of("id = ?", [number(id)])
    if row == none then
      return none
    end
    self.account_of_row(row)
  end

  --" Makes an account and sends the verification email. `422` for an address or password that is not
  acceptable, `409` for an address that is taken. --"
  public fun register(self, email: string, password: string) -> Result<Account, web.Problem>
    let address = email.trim().lower()
    if not regex.matches(address, "^[^@ \t\n]+@[^@ \t\n]+[.][^@ \t\n]+$") or address.len() > 190 then
      return problem<Account>(422, "the email address is not valid")
    end
    let bad = self.password_problem(password)
    if bad != none then
      return problem<Account>(422, bad)
    end
    if self.row_of("email = ?", [Json.string(address)]) != none then
      return problem<Account>(409, "this email address is already registered")
    end
    let hashed = Password.hash(password)
    if hashed.is_err() then
      Log.error("accounts: {hashed.unwrap_err().message}")
      return problem<Account>(500, "the account could not be made")
    end
    let id = q.Query.table(self.options.table).insert(self.db, {
      "email": Json.string(address),
      "password_hash": Json.string(hashed.unwrap()),
      "created_at": number(self.now()),
    })
    if id.is_err() then
      Log.error("accounts: {id.unwrap_err().message}")
      return problem<Account>(409, "this email address is already registered")
    end
    let account = Account { id: id.unwrap(), email: address, verified: false }
    self.send_verification(account)
    Result<Account, web.Problem>.Ok(account)
  end

  fun password_problem(self, password: string) -> string?
    if password.len() < self.options.min_password then
      return "the password must have at least {self.options.min_password} characters"
    end
    -- hashing a huge text would be a way to keep the server busy
    if password.len() > 1024 then
      return "the password is too long"
    end
    none
  end

  -- a hash to check against when the address is unknown, so that both cases take the same time
  fun dummy_hash(self) -> string
    if self.dummy.is_empty() then
      self.dummy.push(Password.hash("not the password of anyone").unwrap())
    end
    self.dummy[0]
  end

  --" Checks an address and a password. `401` for both mistakes alike, `403` when the email must be
  checked first (`Options.require_verified`). --"
  public fun authenticate(self, email: string, password: string) -> Result<Account, web.Problem>
    let row = self.row_of("email = ?", [Json.string(email.trim().lower())])
    if row == none then
      Password.verify(password, self.dummy_hash())
      return problem<Account>(401, "the email or the password is wrong")
    end
    let ok = Password.verify(password, row.password_hash)
    if ok.is_err() or not ok.unwrap() then
      return problem<Account>(401, "the email or the password is wrong")
    end
    if self.options.require_verified and row.verified_at == none then
      return problem<Account>(403, "the email address must be checked first")
    end
    -- the settings of the hash may have aged
    let stale = Password.needs_rehash(row.password_hash)
    if stale.is_ok() and stale.unwrap() then
      let fresh = Password.hash(password)
      if fresh.is_ok() then
        self.db.execute("UPDATE {self.options.table} SET password_hash = ? WHERE id = ?", [Json.string(fresh.unwrap()), number(row.id)])
      end
    end
    Result<Account, web.Problem>.Ok(self.account_of_row(row))
  end

  -- a new token for the account: the text to send, of which only the hash is kept
  fun new_token(self, account_id: int, kind: string, ttl: int) -> Result<string, Error>
    let token = Crypto.token(32)
    if token.is_err() then
      return Result<string, Error>.Err(token.unwrap_err())
    end
    let text = token.unwrap()
    let saved = self.db.execute("INSERT INTO {self.options.table}_tokens (token_hash, account_id, kind, expires_at) VALUES (?, ?, ?, ?)", [Json.string(hash_of(text)), number(account_id), Json.string(kind), number(self.now() + ttl * 1000)])
    if saved.is_err() then
      return Result<string, Error>.Err(saved.unwrap_err())
    end
    Result<string, Error>.Ok(text)
  end

  -- the account a still valid token of this kind belongs to; the token is used up
  fun use_token(self, text: string, kind: string) -> Account?
    let found = self.db.query("SELECT account_id FROM {self.options.table}_tokens WHERE token_hash = ? AND kind = ? AND used_at IS NULL AND expires_at > ?", [Json.string(hash_of(text)), Json.string(kind), number(self.now())])
    if found.is_err() or found.unwrap().is_empty() then
      return none
    end
    -- whoever marks it first wins: two requests with the same link cannot both pass
    let taken = self.db.execute("UPDATE {self.options.table}_tokens SET used_at = ? WHERE token_hash = ? AND used_at IS NULL", [number(self.now()), Json.string(hash_of(text))])
    if taken.is_err() or taken.unwrap() != 1 then
      return none
    end
    self.find(found.unwrap()[0].get("account_id", Json.null()).as_number() as int)
  end

  fun deliver(self, to: string, subject: string, text: string)
    let sent = self.mailer.send(mail.Mail { sender: self.options.sender, to: [to], subject: subject, text: text })
    if sent.is_err() then
      Log.error("accounts: the email to {to} was not sent: {sent.unwrap_err().message}")
    end
  end

  --" Sends the email that lets the account check its address. --"
  public fun send_verification(self, account: Account)
    let token = self.new_token(account.id, "verify", self.options.verify_ttl)
    if token.is_err() then
      Log.error("accounts: {token.unwrap_err().message}")
      return
    end
    let link = "{self.options.base_url}{self.options.verify_path}?token={token.unwrap()}"
    self.deliver(account.email, "Confirm your email address", "Welcome to {self.options.app_name}.\n\nConfirm your email address with this link (valid for a day):\n{link}\n\nIf you did not register, ignore this message.\n")
  end

  --" Checks the address of the account the token was sent to. `400` for a token that is wrong, old or used. --"
  public fun verify_email(self, token: string) -> Result<Account, web.Problem>
    let account = self.use_token(token, "verify")
    if account == none then
      return problem<Account>(400, "the link is not valid or has expired")
    end
    self.db.execute("UPDATE {self.options.table} SET verified_at = ? WHERE id = ? AND verified_at IS NULL", [number(self.now()), number(account.id)])
    Result<Account, web.Problem>.Ok(Account { id: account.id, email: account.email, verified: true })
  end

  --" Sends a reset link when the address has an account. It never says whether it has: the caller
  answers the same thing either way. --"
  public fun start_password_reset(self, email: string)
    let row = self.row_of("email = ?", [Json.string(email.trim().lower())])
    if row == none then
      return
    end
    let token = self.new_token(row.id, "reset", self.options.reset_ttl)
    if token.is_err() then
      Log.error("accounts: {token.unwrap_err().message}")
      return
    end
    let link = "{self.options.base_url}{self.options.reset_path}?token={token.unwrap()}"
    self.deliver(row.email, "Reset your password", "Someone asked to reset the password of your account on {self.options.app_name}.\n\nChoose a new one with this link (valid for an hour):\n{link}\n\nIf it was not you, ignore this message: your password has not changed.\n")
  end

  --" Sets a new password with the token of the email. The other reset links of the account stop working. --"
  public fun reset_password(self, token: string, password: string) -> Result<Account, web.Problem>
    let bad = self.password_problem(password)
    if bad != none then
      return problem<Account>(422, bad)
    end
    let account = self.use_token(token, "reset")
    if account == none then
      return problem<Account>(400, "the link is not valid or has expired")
    end
    let hashed = Password.hash(password)
    if hashed.is_err() then
      return problem<Account>(500, "the password could not be changed")
    end
    self.db.execute("UPDATE {self.options.table} SET password_hash = ? WHERE id = ?", [Json.string(hashed.unwrap()), number(account.id)])
    self.db.execute("UPDATE {self.options.table}_tokens SET used_at = ? WHERE account_id = ? AND kind = 'reset' AND used_at IS NULL", [number(self.now()), number(account.id)])
    Result<Account, web.Problem>.Ok(account)
  end
end

-- ------------------------------------------------------------------------ routes

--" The signed in account of this request, or `none`. --"
fun account_of(req: Request, accounts: Accounts) -> Account?
  let id = sess.session_of(req).get("account_id")
  if id == none then
    return none
  end
  let n = int.parse(id)
  if n == none then
    return none
  end
  accounts.find(n)
end

fun fields(req: Request) -> map<string, string>
  let out: map<string, string> = {}
  let body = req.body ?? ""
  let parsed = Json.parse(body)
  if parsed.is_ok() and parsed.unwrap().is_object() then
    let o = parsed.unwrap().as_object()
    for k in o.keys() do
      let v = o[k] ?? Json.null()
      if v.is_string() then
        out[k] = v.as_string()
      end
    end
    return out
  end
  let form = req.form()
  if form.is_ok() then
    return form.unwrap()
  end
  out
end

fun answer<T>(result: Result<T, web.Problem>, status: int) -> Response
  if result.is_err() then
    return result.unwrap_err().to_response()
  end
  Response.json(Json.of(result.unwrap()).to_text()).with_status(status)
end

fun message(text: string, status: int) -> Response
  Response.json(Json.of({"message": text}).to_text()).with_status(status)
end

--" Adds the routes of the table above under `prefix` (`"/auth"`). The session middleware must be on. --"
fun mount(app: web.App, accounts: Accounts, prefix: string)
  app.post(prefix + "/register", fun(req: Request) -> Response
    let f = fields(req)
    answer(accounts.register(f["email"] ?? "", f["password"] ?? ""), 201)
  end)
  app.post(prefix + "/login", fun(req: Request) -> Response
    let f = fields(req)
    let checked = accounts.authenticate(f["email"] ?? "", f["password"] ?? "")
    if checked.is_ok() then
      let s = sess.session_of(req)
      -- a new identifier: one seen before signing in must not be of any use after
      s.regenerate()
      s.set("account_id", "{checked.unwrap().id}")
    end
    answer(checked, 200)
  end)
  app.post(prefix + "/logout", fun(req: Request) -> Response
    let s = sess.session_of(req)
    s.regenerate()
    s.clear()
    message("signed out", 200)
  end)
  app.get(prefix + "/me", fun(req: Request) -> Response
    let account = account_of(req, accounts)
    if account == none then
      return web.Problem { status: 401, message: "sign in first" }.to_response()
    end
    Response.json(Json.of(account).to_text())
  end)
  app.post(prefix + "/password/forgot", fun(req: Request) -> Response
    accounts.start_password_reset(fields(req)["email"] ?? "")
    message("if this address has an account, an email is on its way", 202)
  end)
  app.post(prefix + "/password/reset", fun(req: Request) -> Response
    let f = fields(req)
    answer(accounts.reset_password(f["token"] ?? "", f["password"] ?? ""), 200)
  end)
  app.post(prefix + "/email/verify", fun(req: Request) -> Response
    answer(accounts.verify_email(fields(req)["token"] ?? ""), 200)
  end)
  app.get(prefix + "/email/verify", fun(req: Request) -> Response
    answer(accounts.verify_email(req.query["token"] ?? ""), 200)
  end)
  app.post(prefix + "/email/resend", fun(req: Request) -> Response
    let account = account_of(req, accounts)
    if account == none then
      return web.Problem { status: 401, message: "sign in first" }.to_response()
    end
    if not account.verified then
      accounts.send_verification(account)
    end
    message("if the address still has to be checked, an email is on its way", 202)
  end)
end

--" A guard: the request must come from a signed in account (`401` otherwise). The account is kept for
the route (`account_of`). --"
fun require_login(accounts: Accounts) -> web.GuardFn
  fun(req: Request) -> Response?
    if account_of(req, accounts) == none then
      return web.Problem { status: 401, message: "sign in first" }.to_response()
    end
    none
  end
end

--" A guard: signed in **and** with a checked email (`403` when the address is not checked yet). --"
fun require_verified(accounts: Accounts) -> web.GuardFn
  fun(req: Request) -> Response?
    let account = account_of(req, accounts)
    if account == none then
      return web.Problem { status: 401, message: "sign in first" }.to_response()
    end
    if not account.verified then
      return web.Problem { status: 403, message: "check your email address first" }.to_response()
    end
    none
  end
end

export Options, Account, Accounts, mount, account_of, require_login, require_verified

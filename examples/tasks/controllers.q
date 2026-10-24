-- The routes: functions and a controller whose parameters say where their values come from.
import "../../web/app.q" as web
import "../../web/validate.q" as v
import "../../web/session.q" as session
import "../../web/auth.q" as auth
import "../../jwt.q" as jwt
import User, Users, Task, Tasks, Me, Config from "providers.q"

struct Credentials
  #[v.Email]
  public email: string
  #[v.Length(8, 100)]
  public password: string
end

struct NewTask
  #[v.NotBlank, v.Length(1, 120)]
  public title: string
end

struct Health
  public status: string
end

#[web.Get("/health")]
fun health() -> Health
  Health { status: "ok" }
end

#[web.Post("/register")]
#[web.Status(201)]
fun register(#[web.Body] input: Credentials, users: Users) -> Result<User, HttpError>
  if users.by_email(input.email) != none then
    return Result<User, HttpError>.Err(HttpError { status: 409, message: "this email is already used" })
  end
  let made = users.register(input.email, input.password)
  if made.is_err() then
    Log.error(made.unwrap_err().message)
    return Result<User, HttpError>.Err(HttpError { status: 500, message: "could not register" })
  end
  Result<User, HttpError>.Ok(made.unwrap())
end

#[web.Post("/login")]
fun login(#[web.Body] input: Credentials, users: Users, req: Request) -> Result<User, HttpError>
  let row = users.by_email(input.email)
  let refused = HttpError { status: 401, message: "wrong email or password" }
  if row == none then
    return Result<User, HttpError>.Err(refused)
  end
  let ok = Password.verify(input.password, row.password_hash)
  if ok.is_err() or not ok.unwrap() then
    return Result<User, HttpError>.Err(refused)
  end
  let s = session.session_of(req)
  s.set("user", "{row.id}")
  Result<User, HttpError>.Ok(User { id: row.id, email: row.email })
end

--" What a token says about the user. --"
struct Session
  public sub: string
  public email: string
  public iat: int
  public exp: int
end

struct TokenResponse
  public access_token: string
  public token_type: string
  public expires_in: int
end

--" Trades an email and a password for a token, for clients that are not browsers. --"
#[web.Post("/token")]
fun token(#[web.Body] input: Credentials, users: Users, config: Config) -> Result<TokenResponse, HttpError>
  let row = users.by_email(input.email)
  let refused = HttpError { status: 401, message: "wrong email or password" }
  if row == none then
    return Result<TokenResponse, HttpError>.Err(refused)
  end
  let ok = Password.verify(input.password, row.password_hash)
  if ok.is_err() or not ok.unwrap() then
    return Result<TokenResponse, HttpError>.Err(refused)
  end
  let now = time.now() div 1000
  let signed = jwt.sign(Session { sub: "{row.id}", email: row.email, iat: now, exp: now + 900 }, jwt.Key.hs256(config.secret))
  if signed.is_err() then
    Log.error(signed.unwrap_err().message)
    return Result<TokenResponse, HttpError>.Err(HttpError { status: 500, message: "could not make a token" })
  end
  Result<TokenResponse, HttpError>.Ok(TokenResponse { access_token: signed.unwrap(), token_type: "Bearer", expires_in: 900 })
end

--" Who the token says you are: the route is guarded by `jwt`, no session and no database. --"
#[web.Get("/api/me")]
#[web.Guard("jwt")]
fun api_me(req: Request) -> Session?
  auth.claims_of<Session>(req)
end

#[web.Post("/logout")]
fun logout(req: Request) -> Response
  session.session_of(req).clear()
  Response { status: 204, body: "" }
end

#[web.Get("/me")]
#[web.Guard("auth")]
fun me(who: Me) -> Me
  who
end

--" The tasks of the signed-in user: every route of this controller needs the `auth` guard. --"
#[web.Controller("/tasks")]
#[web.Guard("auth")]
struct TaskController
end

impl TaskController
  #[web.Get("/")]
  public fun list(self, who: Me, tasks: Tasks, #[web.Query] done: bool?) -> array<Task>
    tasks.for_user(who.id, done)
  end

  #[web.Get("/:id")]
  public fun show(self, #[web.Path] id: int, who: Me, tasks: Tasks) -> Task?
    tasks.find(who.id, id)
  end

  #[web.Post("/")]
  #[web.Status(201)]
  public fun create(self, #[web.Body] input: NewTask, who: Me, tasks: Tasks) -> Task
    tasks.add(who.id, input.title)
  end

  #[web.Post("/:id/done")]
  public fun finish(self, #[web.Path] id: int, who: Me, tasks: Tasks) -> Task?
    tasks.finish(who.id, id)
  end

  #[web.Delete("/:id")]
  public fun remove(self, #[web.Path] id: int, who: Me, tasks: Tasks) -> Response
    if tasks.remove(who.id, id) then
      Response { status: 204, body: "" }
    else
      web.Problem { status: 404, message: "no such task" }.to_response()
    end
  end
end

export TaskController, Credentials, NewTask, Session, TokenResponse

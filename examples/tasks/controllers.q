-- The routes: functions and a controller whose parameters say where their values come from.
import "../../web/app.q" as web
import "../../web/validate.q" as v
import "../../web/session.q" as session
import User, Users, Task, Tasks, Me from "providers.q"

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

export TaskController, Credentials, NewTask

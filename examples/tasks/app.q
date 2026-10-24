-- Puts the application together. `main.q` serves it, the tests send requests to it.
import "../../web/app.q" as web
import "../../web/middleware.q" as mw
import "../../web/session.q" as session
import "providers.q" as providers
import "controllers.q" as controllers
import Config, Me, Users from "providers.q"

fun build() -> web.App
  let app = web.App.new(Reflect.callables(providers))
  let config = app.container.get<Config>().unwrap()

  app.use(mw.request_id())
  app.use(mw.logging())
  app.use(mw.security_headers())
  app.use(session.sessions(config.secret))

  -- the guard: who is signed in? `none` lets the request through.
  app.guard("auth", fun(req: Request) -> Response?
    let id = int.parse(session.session_of(req).get("user") ?? "")
    if id == none then
      return web.Problem { status: 401, message: "sign in first" }.to_response()
    end
    let users = app.container.get<Users>().unwrap()
    let row = users.by_id(id)
    if row == none then
      return web.Problem { status: 401, message: "sign in first" }.to_response()
    end
    req.attrs["me"] = Any.of(Me { id: row.id, email: row.email })
    none
  end)

  app.controllers(Reflect.callables(controllers))
  app.controller(controllers.TaskController {})
  app
end

export build

-- A small JSON API:  qlang serve examples/blog/main.q --dev
--   curl localhost:8080/posts
--   curl -X POST localhost:8080/posts -H 'X-User: ada' -d '{"title": "Second", "body": "Hi"}'
import "../../web/app.q" as web
import "../../web/middleware.q" as mw
import "providers.q" as providers
import "controllers.q" as controllers

let app = web.App.new(Reflect.callables(providers))
app.controllers(Reflect.callables(controllers))
app.use(mw.request_id())
app.use(mw.logging())
app.use(mw.security_headers())

let problems = app.validate()
if not problems.is_empty() then
  for p in problems do
    Log.error(p)
  end
  panic("the application is not wired correctly")
end

fun handle(req: Request) -> Response
  app.handle(req)
end

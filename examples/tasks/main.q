-- A task list API:  qlang serve examples/tasks/main.q --dev
--   curl -c jar -X POST localhost:8080/register -d '{"email":"ada@example.org","password":"correct horse"}'
--   curl -c jar -b jar -X POST localhost:8080/login -d '{"email":"ada@example.org","password":"correct horse"}'
--   curl -b jar -X POST localhost:8080/tasks -d '{"title":"Write the guide"}'
--   curl -b jar localhost:8080/tasks
import "app.q" as tasks

let app = tasks.build()
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

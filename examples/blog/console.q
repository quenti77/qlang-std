-- The blog from the command line:  qlang run examples/blog/console.q -- posts:list
--   qlang run examples/blog/console.q -- help
--   qlang run examples/blog/console.q -- routes:list
--   qlang run examples/blog/console.q -- posts:add "A title" --author ada
import "../../cli.q" as cli
import "../../web/app.q" as web
import "../../web/commands.q" as stock
import "providers.q" as providers
import "controllers.q" as controllers
import "commands.q" as commands

let app = web.App.new(Reflect.callables(providers))
app.controllers(Reflect.callables(controllers))

let program = cli.Cli.new(Reflect.callables(providers))
program.named("blog")
program.container.set(app)
program.add(Reflect.callables(commands))
program.add(Reflect.callables(stock).filter(fun(c: Callable) -> bool c.name == "routes_list" end))
program.main()

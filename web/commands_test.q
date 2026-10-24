import "app.q" as web
import "migrate.q" as mig
import "commands.q" as commands
import "../cli.q" as cli
import "../i18n.q" as i18n
import "test_blog.q" as blog
import "test_blog_controllers.q" as controllers

fun build() -> cli.Cli
  let app = web.App.new(Reflect.callables(blog))
  app.controllers(Reflect.callables(controllers))
  let db = Db.connect("sqlite://:memory:").unwrap()
  let tr = i18n.Translator.new("en")
  tr.add("en", "a", "A")
  tr.add("en", "b", "B")
  tr.add("fr", "a", "A")
  let program = cli.Cli.new([])
  program.container.set(app)
  program.container.set(mig.Migrator.new(db))
  program.container.set(commands.Migrations { list: [
    mig.Migration { id: "001_posts", up: ["CREATE TABLE posts (id INTEGER)"], down: ["DROP TABLE posts"] },
    mig.Migration { id: "002_tags", up: ["CREATE TABLE tags (id INTEGER)"], down: ["DROP TABLE tags"] },
  ] })
  program.container.set(tr)
  program.add(Reflect.callables(commands))
  program
end

fun run(program: cli.Cli, args: array<string>) -> (int, string, string)
  let console = cli.Console.captured([])
  let code = program.run(args, console)
  (code, console.output(), console.errors())
end

fun test_the_commands_are_wired()
  assert_eq(build().validate(), [])
end

fun test_routes_are_listed()
  let r = run(build(), ["routes:list"])
  assert_eq(r.0, 0)
  assert(r.1.contains("GET"))
  assert(r.1.contains("/posts/:id"))
  assert(r.1.contains("show"))
end

fun test_migrations_run_report_and_roll_back()
  let program = build()
  let first = run(program, ["db:migrate"])
  assert_eq(first.0, 0)
  assert(first.1.contains("Migrated 001_posts"))
  assert(run(program, ["db:migrate"]).1.contains("Nothing to migrate"))
  assert(run(program, ["db:status"]).1.contains("applied"))
  let back = run(program, ["db:rollback", "--steps", "1"])
  assert(back.1.contains("Rolled back 002_tags"))
  assert(run(program, ["db:status"]).1.contains("pending"))
end

fun test_missing_translations_are_listed_with_exit_code_1()
  let program = build()
  let r = run(program, ["locale:missing", "fr"])
  assert_eq(r.0, 1)
  assert_eq(r.1, "b")
  assert_eq(run(program, ["locale:missing", "en"]).0, 0)
end

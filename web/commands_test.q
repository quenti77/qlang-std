import "app.q" as web
import "migrate.q" as mig
import "commands.q" as commands
import "../cli.q" as cli
import "../i18n.q" as i18n
import "../queue.q" as jobs
import "../schedule.q" as sch
import "cache.q" as cc
import "test_blog.q" as blog
import "test_blog_controllers.q" as controllers

struct Ping
  public ok: bool
end

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
  let queue = jobs.Queue.new(db, "sqlite")
  queue.install().unwrap()
  queue.max_attempts = 1
  queue.handle<Ping>(fun(p: Ping) -> string? if p.ok then none else "refused" end end)
  program.container.set(queue)
  let plan = sch.Schedule.new(cc.Cache.memory())
  plan.clock = fun() -> int 1700000000000 end
  plan.cron("always", "* * * * *", fun() -> string? none end)
  program.container.set(plan)
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

fun test_the_queue_commands_work_and_list_what_failed()
  let program = build()
  let queue = program.container.get<jobs.Queue>().unwrap()
  queue.push(Ping { ok: true }).unwrap()
  queue.push(Ping { ok: false }).unwrap()
  assert(run(program, ["queue:work", "--once"]).1.contains("2 job(s) done"))
  let failed = run(program, ["queue:failed"])
  assert(failed.1.contains("refused"))
  assert_eq(run(program, ["queue:retry", "999"]).0, 1)
  let id = "{queue.failed().unwrap()[0].id}"
  assert(run(program, ["queue:retry", id]).1.contains("back in the queue"))
end

fun test_schedule_run_runs_the_tasks_that_are_due_once_per_minute()
  let program = build()
  assert(run(program, ["schedule:run"]).1.contains("1 task(s) run"))
  assert(run(program, ["schedule:run"]).1.contains("0 task(s) run"))
end

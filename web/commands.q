--" # Ready-made commands

Commands for `cli.q` that every web application wants. Add them to the program next to your own:

```
let app = cli.Cli.new(Reflect.callables(providers))
app.container.set(web_app)                          -- the web.App, for `routes:list`
app.container.set(Migrations { list: my_migrations })
app.container.set(translator)                       -- for `locale:missing`
app.add(Reflect.callables(commands))                -- these ones
app.add(Reflect.callables(my_commands))
app.main()
```

| Command | Does | Needs in the container |
| --- | --- | --- |
| `routes:list` | one line for each route: method, path, handler | `web.App` |
| `db:migrate` | applies the migrations that were not yet | `Migrator`, `Migrations` |
| `db:rollback --steps 1` | undoes the last migrations | `Migrator`, `Migrations` |
| `db:status` | which migrations are applied | `Migrator`, `Migrations` |
| `queue:work` (`--once`) | does the jobs of the queue, waiting for new ones unless `--once` | `Queue` (with its handlers) |
| `queue:failed` | the jobs that gave up | `Queue` |
| `queue:retry <id>` | puts a failed job back in the queue | `Queue` |
| `locale:missing fr` | the keys of the default language that `fr` lacks (exit code `1` if any) | `Translator` |

A command whose services the container lacks is reported by `Cli.validate()`, so only add the ones
you can serve.
--"
import "../cli.q" as cli
import "../i18n.q" as i18n
import "app.q" as web
import "migrate.q" as mig
import "../queue.q" as jobs

--" The migrations of the application, as a service. --"
struct Migrations
  public list: array<mig.Migration>
end

#[cli.Command("routes:list", "Lists the routes")]
fun routes_list(app: web.App, console: cli.Console)
  let rows: array<array<string>> = []
  for r in app.route_list() do
    let source = r.source
    rows.push([r.method, r.pattern, if source == none then "(function)" else source.name end])
  end
  console.table(["method", "path", "handler"], rows)
end

#[cli.Command("db:migrate", "Applies the migrations that were not yet")]
fun db_migrate(migrator: mig.Migrator, migrations: Migrations, console: cli.Console) -> Result<int, Error>
  let done = migrator.run(migrations.list)
  if done.is_err() then
    return Result<int, Error>.Err(done.unwrap_err())
  end
  let ids = done.unwrap()
  if ids.len() == 0 then
    console.line("Nothing to migrate")
  end
  for id in ids do
    console.line("Migrated {id}")
  end
  Result<int, Error>.Ok(0)
end

#[cli.Command("db:rollback", "Undoes the last migrations")]
fun db_rollback(migrator: mig.Migrator, migrations: Migrations, console: cli.Console, #[cli.Opt(description: "how many migrations to undo")] steps: int?) -> Result<int, Error>
  let done = migrator.rollback(migrations.list, steps ?? 1)
  if done.is_err() then
    return Result<int, Error>.Err(done.unwrap_err())
  end
  for id in done.unwrap() do
    console.line("Rolled back {id}")
  end
  Result<int, Error>.Ok(0)
end

#[cli.Command("db:status", "Shows which migrations are applied")]
fun db_status(migrator: mig.Migrator, migrations: Migrations, console: cli.Console) -> Result<int, Error>
  let found = migrator.status(migrations.list)
  if found.is_err() then
    return Result<int, Error>.Err(found.unwrap_err())
  end
  let rows: array<array<string>> = []
  for s in found.unwrap() do
    rows.push([s.id, if s.applied then "applied" else "pending" end])
  end
  console.table(["migration", "state"], rows)
  Result<int, Error>.Ok(0)
end

#[cli.Command("locale:missing", "Lists the messages a language still lacks")]
fun locale_missing(#[cli.Arg(description: "the language to check")] locale: string, translator: i18n.Translator, console: cli.Console) -> int
  let lacking = translator.missing(locale)
  for key in lacking do
    console.line(key)
  end
  if lacking.len() > 0 then 1 else 0 end
end

#[cli.Command("queue:work", "Does the jobs of the queue")]
fun queue_work(queue: jobs.Queue, console: cli.Console, #[cli.Opt(description: "stop when no job is due")] once: bool) -> Result<int, Error>
  let done = queue.work(once)
  if done.is_err() then
    return Result<int, Error>.Err(done.unwrap_err())
  end
  console.line("{done.unwrap()} job(s) done")
  Result<int, Error>.Ok(0)
end

#[cli.Command("queue:failed", "Lists the jobs that gave up")]
fun queue_failed(queue: jobs.Queue, console: cli.Console) -> Result<int, Error>
  let found = queue.failed()
  if found.is_err() then
    return Result<int, Error>.Err(found.unwrap_err())
  end
  console.table(["id", "type", "attempts", "error"], found.unwrap().map(fun(j: jobs.FailedJob) -> array<string> [j.id, j.kind, "{j.attempts}", j.error] end))
  Result<int, Error>.Ok(0)
end

#[cli.Command("queue:retry", "Puts a failed job back in the queue")]
fun queue_retry(#[cli.Arg(description: "the id shown by queue:failed")] id: string, queue: jobs.Queue, console: cli.Console) -> Result<int, Error>
  let again = queue.retry_failed(id)
  if again.is_err() then
    return Result<int, Error>.Err(again.unwrap_err())
  end
  if not again.unwrap() then
    console.error("no failed job {id}")
    return Result<int, Error>.Ok(1)
  end
  console.line("job {id} is back in the queue")
  Result<int, Error>.Ok(0)
end

export Migrations

-- The worker process:  qlang run examples/deploy/worker.q
-- It leaves cleanly on SIGTERM (after the job it is doing), so a deployment never cuts a job in two.
import "../../queue.q" as jobs

struct Hello
  public name: string
end

let db = Db.connect(env.get("DATABASE_URL") ?? "sqlite://app.db").unwrap()
let queue = jobs.Queue.new(db, "sqlite")
queue.install().unwrap()
queue.handle<Hello>(fun(h: Hello) -> string?
  Log.info("hello, {h.name}")
  none
end)
let done = queue.work_with(jobs.WorkOptions { max_seconds: 3600 })
if done.is_err() then
  Log.error("worker stopped: {done.unwrap_err().message}")
else
  Log.info("worker stopped after {done.unwrap()} job(s)")
end

--" # Job queue

Work that should not be done during a request (sending a mail, resizing an image, calling a slow
service) is written down as a *job* and done later by a worker. The jobs live in a table of your
database, so there is nothing else to run.

```
struct SendWelcome
  public email: string
end

let queue = Queue.new(db, "sqlite")
queue.install().unwrap()                                   -- the tables, once (`CREATE TABLE IF NOT EXISTS`)
queue.handle<SendWelcome>(fun(job: SendWelcome) -> string?
  let sent = mailer.send(job.email, "Welcome")
  if sent.is_err() then sent.unwrap_err().message else none end     -- none: done; a text: why it failed
end)

queue.push(SendWelcome { email: "ada@example.org" }).unwrap()       -- in a route
queue.push_in(SendWelcome { email: "bob@example.org" }, 3600).unwrap()   -- not before an hour

queue.work(false)                                          -- in a worker process: never returns
```

A job is any structure with public fields (it is stored as JSON); its type finds its handler. A
handler returns `none` when it did the job, or a text that says why it could not: the job is tried
again later (after 10 s, 1 min, 5 min, then every 15 min) up to `max_attempts` times (3 by default),
then it moves to the table of failed jobs, where `failed`, `retry_failed` and `forget_failed` reach it.
A handler must not `panic`: that stops the worker.

Several workers may run at once: each takes a job by marking it before it runs it. A job that stays
marked longer than `timeout` seconds (the worker died) becomes available again, so a handler should be
safe to run twice. Run the worker as a separate process, for example `qlang run worker.q` under
systemd, or with the `queue:work` command of `web/commands.q`.
--"

--" A job the queue holds. --"
struct JobRow
  public id: int
  public kind: string
  public payload: string
  public attempts: int
end

--" A job that gave up. --"
struct FailedJob
  public id: int
  public kind: string
  public payload: string
  public attempts: int
  public error: string
end

--" The queue and its handlers. --"
struct Queue
  public db: Db
  public dialect: string
  --" The name of the table of waiting jobs; the failed ones are in `{table}_failed`. --"
  public table: string
  public max_attempts: int
  --" Seconds after which a job that is still marked as running is given to another worker. --"
  public timeout: int
  --" The time in milliseconds; tests give their own. --"
  public clock: fun() -> int
  handlers: map<string, fun(Json) -> string?>
end

fun id_column(dialect: string) -> string
  if dialect == "postgres" then
    return "BIGSERIAL PRIMARY KEY"
  end
  if dialect == "mysql" then
    return "BIGINT AUTO_INCREMENT PRIMARY KEY"
  end
  "INTEGER PRIMARY KEY AUTOINCREMENT"
end

fun queue_error<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
end

--" Seconds to wait before attempt number `attempt + 1`. --"
fun backoff(attempt: int) -> int
  if attempt <= 1 then
    return 10
  end
  if attempt == 2 then
    return 60
  end
  if attempt == 3 then
    return 300
  end
  900
end

fun number(n: int) -> Json
  Json.number(n as float)
end

impl Queue
  --" A queue in `db`; `dialect` is `"sqlite"`, `"postgres"` or `"mysql"` (it only changes how the tables
  are made). --"
  public fun new(db: Db, dialect: string) -> Queue
    Queue { db: db, dialect: dialect, table: "jobs", max_attempts: 3, timeout: 300, clock: fun() -> int time.now() end, handlers: {} }
  end

  --" Makes the tables if they do not exist. --"
  public fun install(self) -> Result<bool, Error>
    let id = id_column(self.dialect)
    let made = self.db.execute("CREATE TABLE IF NOT EXISTS {self.table} (id {id}, kind VARCHAR(255) NOT NULL, payload TEXT NOT NULL, attempts BIGINT NOT NULL, available_at BIGINT NOT NULL, reserved_at BIGINT, created_at BIGINT NOT NULL, last_error TEXT)", [])
    if made.is_err() then
      return Result<bool, Error>.Err(made.unwrap_err())
    end
    let failed = self.db.execute("CREATE TABLE IF NOT EXISTS {self.table}_failed (id {id}, kind VARCHAR(255) NOT NULL, payload TEXT NOT NULL, attempts BIGINT NOT NULL, error TEXT NOT NULL, failed_at BIGINT NOT NULL)", [])
    if failed.is_err() then
      return Result<bool, Error>.Err(failed.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" Says what to do with the jobs of type `T`: `none` when it is done, otherwise why it failed. --"
  public fun handle<T>(self, handler: fun(T) -> string?)
    self.handlers[Reflect.type_name<T>()] = fun(payload: Json) -> string?
      let read = Json.to<T>(payload)
      if read.is_err() then
        return "the job cannot be read: {read.unwrap_err().message}"
      end
      handler(read.unwrap())
    end
  end

  --" Writes a job down, to be done as soon as a worker is free. --"
  public fun push<T>(self, job: T) -> Result<bool, Error>
    self.push_in<T>(job, 0)
  end

  --" Writes a job down, to be done after `seconds`. --"
  public fun push_in<T>(self, job: T, seconds: int) -> Result<bool, Error>
    let now = self.clock()
    let saved = self.db.execute("INSERT INTO {self.table} (kind, payload, attempts, available_at, created_at) VALUES (?, ?, 0, ?, ?)", [Json.string(Reflect.type_name<T>()), Json.string(Json.of(job).to_text()), number(now + seconds * 1000), number(now)])
    if saved.is_err() then
      return Result<bool, Error>.Err(saved.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" How many jobs wait (or run). --"
  public fun pending(self) -> Result<int, Error>
    let rows = self.db.query("SELECT COUNT(*) AS n FROM {self.table}", [])
    if rows.is_err() then
      return Result<int, Error>.Err(rows.unwrap_err())
    end
    Result<int, Error>.Ok(rows.unwrap()[0].get("n", Json.null()).as_number() as int)
  end

  fun release_stale(self) -> Result<bool, Error>
    let limit = self.clock() - self.timeout * 1000
    let freed = self.db.execute("UPDATE {self.table} SET reserved_at = NULL WHERE reserved_at IS NOT NULL AND reserved_at < ?", [number(limit)])
    if freed.is_err() then
      return Result<bool, Error>.Err(freed.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" Takes the oldest job that is due and marks it as running; `none` when there is none. --"
  fun claim(self) -> Result<JobRow?, Error>
    let now = self.clock()
    let rows = self.db.query("SELECT id, kind, payload, attempts FROM {self.table} WHERE reserved_at IS NULL AND available_at <= ? ORDER BY id ASC LIMIT 5", [number(now)])
    if rows.is_err() then
      return Result<JobRow?, Error>.Err(rows.unwrap_err())
    end
    for row in rows.unwrap() do
      let id = row.get("id", Json.null()).as_number() as int
      -- whoever changes the row first wins
      let taken = self.db.execute("UPDATE {self.table} SET reserved_at = ?, attempts = attempts + 1 WHERE id = ? AND reserved_at IS NULL", [number(now), number(id)])
      if taken.is_err() then
        return Result<JobRow?, Error>.Err(taken.unwrap_err())
      end
      if taken.unwrap() == 1 then
        let job = JobRow { id: id, kind: row.get("kind", Json.null()).as_string(), payload: row.get("payload", Json.null()).as_string(), attempts: row.get("attempts", Json.null()).as_number() as int + 1 }
        return Result<JobRow?, Error>.Ok(job)
      end
    end
    Result<JobRow?, Error>.Ok(none)
  end

  fun give_up(self, job: JobRow, why: string) -> Result<bool, Error>
    let moved = self.db.execute("INSERT INTO {self.table}_failed (kind, payload, attempts, error, failed_at) VALUES (?, ?, ?, ?, ?)", [Json.string(job.kind), Json.string(job.payload), number(job.attempts), Json.string(why), number(self.clock())])
    if moved.is_err() then
      return Result<bool, Error>.Err(moved.unwrap_err())
    end
    let gone = self.db.execute("DELETE FROM {self.table} WHERE id = ?", [number(job.id)])
    if gone.is_err() then
      return Result<bool, Error>.Err(gone.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" Does the next due job. Gives `true` when there was one (done or failed), `false` when none was due. --"
  public fun work_one(self) -> Result<bool, Error>
    let freed = self.release_stale()
    if freed.is_err() then
      return Result<bool, Error>.Err(freed.unwrap_err())
    end
    let claimed = self.claim()
    if claimed.is_err() then
      return Result<bool, Error>.Err(claimed.unwrap_err())
    end
    let job = claimed.unwrap()
    if job == none then
      return Result<bool, Error>.Ok(false)
    end
    let handler = self.handlers[job.kind]
    let outcome: string? = none
    if handler == none then
      let gave = self.give_up(job, "no handler for {job.kind}")
      if gave.is_err() then
        return Result<bool, Error>.Err(gave.unwrap_err())
      end
      Log.error("job {job.id}: no handler for {job.kind}")
      return Result<bool, Error>.Ok(true)
    end
    let payload = Json.parse(job.payload)
    if payload.is_err() then
      self.give_up(job, "the payload is not JSON")
      return Result<bool, Error>.Ok(true)
    end
    let why = handler(payload.unwrap())
    if why == none then
      let done = self.db.execute("DELETE FROM {self.table} WHERE id = ?", [number(job.id)])
      if done.is_err() then
        return Result<bool, Error>.Err(done.unwrap_err())
      end
      return Result<bool, Error>.Ok(true)
    end
    Log.warn("job {job.id} ({job.kind}) failed, attempt {job.attempts}: {why}")
    if job.attempts >= self.max_attempts then
      let gave = self.give_up(job, why)
      if gave.is_err() then
        return Result<bool, Error>.Err(gave.unwrap_err())
      end
      Log.error("job {job.id} ({job.kind}) gave up after {job.attempts} attempts")
      return Result<bool, Error>.Ok(true)
    end
    let later = self.clock() + backoff(job.attempts) * 1000
    let kept = self.db.execute("UPDATE {self.table} SET reserved_at = NULL, available_at = ?, last_error = ? WHERE id = ?", [number(later), Json.string(why), number(job.id)])
    if kept.is_err() then
      return Result<bool, Error>.Err(kept.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" Does the due jobs. With `once`, ends when none is due; otherwise it waits for new ones and never
  returns. A database error ends it with that error. --"
  public fun work(self, once: bool) -> Result<int, Error>
    let done = 0
    while true do
      let turn = self.work_one()
      if turn.is_err() then
        return Result<int, Error>.Err(turn.unwrap_err())
      end
      if turn.unwrap() then
        done += 1
      else
        if once then
          return Result<int, Error>.Ok(done)
        end
        time.sleep(1000)
      end
    end
    Result<int, Error>.Ok(done)
  end

  --" The jobs that gave up, oldest first. --"
  public fun failed(self) -> Result<array<FailedJob>, Error>
    let rows = self.db.query("SELECT id, kind, payload, attempts, error FROM {self.table}_failed ORDER BY id ASC", [])
    if rows.is_err() then
      return Result<array<FailedJob>, Error>.Err(rows.unwrap_err())
    end
    let out: array<FailedJob> = []
    for row in rows.unwrap() do
      out.push(FailedJob { id: row.get("id", Json.null()).as_number() as int, kind: row.get("kind", Json.null()).as_string(), payload: row.get("payload", Json.null()).as_string(), attempts: row.get("attempts", Json.null()).as_number() as int, error: row.get("error", Json.null()).as_string() })
    end
    Result<array<FailedJob>, Error>.Ok(out)
  end

  --" Puts a failed job back in the queue, with a fresh count of attempts. `false` if there is none with this id. --"
  public fun retry_failed(self, id: int) -> Result<bool, Error>
    let rows = self.db.query("SELECT kind, payload FROM {self.table}_failed WHERE id = ?", [number(id)])
    if rows.is_err() then
      return Result<bool, Error>.Err(rows.unwrap_err())
    end
    let found = rows.unwrap()
    if found.is_empty() then
      return Result<bool, Error>.Ok(false)
    end
    let now = self.clock()
    let again = self.db.execute("INSERT INTO {self.table} (kind, payload, attempts, available_at, created_at) VALUES (?, ?, 0, ?, ?)", [found[0].get("kind", Json.null()), found[0].get("payload", Json.null()), number(now), number(now)])
    if again.is_err() then
      return Result<bool, Error>.Err(again.unwrap_err())
    end
    self.forget_failed(id)
  end

  --" Deletes a failed job. `false` if there is none with this id. --"
  public fun forget_failed(self, id: int) -> Result<bool, Error>
    let gone = self.db.execute("DELETE FROM {self.table}_failed WHERE id = ?", [number(id)])
    if gone.is_err() then
      return Result<bool, Error>.Err(gone.unwrap_err())
    end
    Result<bool, Error>.Ok(gone.unwrap() > 0)
  end
end

export Queue, JobRow, FailedJob

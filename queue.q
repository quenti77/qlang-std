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

Three drivers keep the jobs: your SQL database (`Queue.new(db, "sqlite")`, nothing else to run, and a
job pushed in a transaction only exists when it commits), or **Redis** (`Queue.redis(redis, "default")`:
workers wait on the list instead of polling, as in Laravel's Redis queue). The rest of the code is the same.

A job is any structure with public fields (it is stored as JSON); its type finds its handler. A
handler returns `none` when it did the job, or a text that says why it could not: the job is tried
again later (after 10 s, 1 min, 5 min, then every 15 min) up to `max_attempts` times (3 by default),
then it moves to the list of failed jobs, where `failed`, `retry_failed` and `forget_failed` reach it.
A handler must not `panic`: that stops the worker.

Several workers may run at once: each takes a job by marking it before it runs it. A job that stays
marked longer than `timeout` seconds (the worker died) becomes available again, so a handler should be
safe to run twice. Run the worker as a separate process, for example `qlang run worker.q` under
systemd, or with the `queue:work` command of `web/commands.q`.
--"

--" A job the queue holds. `id` and `token` belong to the driver. --"
struct JobRow
  public id: string
  public kind: string
  public payload: string
  public attempts: int
  public token: string
end

--" A job that gave up. --"
struct FailedJob
  public id: string
  public kind: string
  public payload: string
  public attempts: int
  public error: string
end

--" Where the jobs are kept: what a `Queue` needs from the database or from Redis. Times are in
milliseconds. --"
trait QueueDriver
  fun install(self) -> Result<bool, Error>
  fun push(self, kind: string, payload: string, available_at: int, now: int) -> Result<bool, Error>
  --" The oldest job that is due (and marks it as running), waiting up to `wait` seconds for one if
  the driver can wait. --"
  fun claim(self, now: int, timeout: int, wait: int) -> Result<JobRow?, Error>
  --" Whether `claim` waits by itself (so the worker has no need to sleep). --"
  fun waits(self) -> bool
  fun done(self, job: JobRow) -> Result<bool, Error>
  fun release(self, job: JobRow, available_at: int, why: string) -> Result<bool, Error>
  fun fail(self, job: JobRow, why: string, now: int) -> Result<bool, Error>
  fun pending(self) -> Result<int, Error>
  fun failed(self) -> Result<array<FailedJob>, Error>
  fun retry_failed(self, id: string, now: int) -> Result<bool, Error>
  fun forget_failed(self, id: string) -> Result<bool, Error>
end

fun number(n: int) -> Json
  Json.number(n as float)
end

fun queue_error<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
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

--" The jobs in a SQL database. --"
struct DbDriver
  public db: Db
  public dialect: string
  --" The name of the table of waiting jobs; the failed ones are in `{table}_failed`. --"
  public table: string
end

impl QueueDriver for DbDriver
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

  public fun push(self, kind: string, payload: string, available_at: int, now: int) -> Result<bool, Error>
    let saved = self.db.execute("INSERT INTO {self.table} (kind, payload, attempts, available_at, created_at) VALUES (?, ?, 0, ?, ?)", [Json.string(kind), Json.string(payload), number(available_at), number(now)])
    if saved.is_err() then
      return Result<bool, Error>.Err(saved.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  public fun waits(self) -> bool
    false
  end

  public fun claim(self, now: int, timeout: int, wait: int) -> Result<JobRow?, Error>
    -- a job left running for too long goes back
    let freed = self.db.execute("UPDATE {self.table} SET reserved_at = NULL WHERE reserved_at IS NOT NULL AND reserved_at < ?", [number(now - timeout * 1000)])
    if freed.is_err() then
      return Result<JobRow?, Error>.Err(freed.unwrap_err())
    end
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
        let job = JobRow { id: "{id}", kind: row.get("kind", Json.null()).as_string(), payload: row.get("payload", Json.null()).as_string(), attempts: row.get("attempts", Json.null()).as_number() as int + 1, token: "{id}" }
        return Result<JobRow?, Error>.Ok(job)
      end
    end
    Result<JobRow?, Error>.Ok(none)
  end

  public fun done(self, job: JobRow) -> Result<bool, Error>
    let gone = self.db.execute("DELETE FROM {self.table} WHERE id = ?", [Json.number((int.parse(job.id) ?? 0) as float)])
    if gone.is_err() then
      return Result<bool, Error>.Err(gone.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  public fun release(self, job: JobRow, available_at: int, why: string) -> Result<bool, Error>
    let kept = self.db.execute("UPDATE {self.table} SET reserved_at = NULL, available_at = ?, last_error = ? WHERE id = ?", [number(available_at), Json.string(why), Json.number((int.parse(job.id) ?? 0) as float)])
    if kept.is_err() then
      return Result<bool, Error>.Err(kept.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  public fun fail(self, job: JobRow, why: string, now: int) -> Result<bool, Error>
    let moved = self.db.execute("INSERT INTO {self.table}_failed (kind, payload, attempts, error, failed_at) VALUES (?, ?, ?, ?, ?)", [Json.string(job.kind), Json.string(job.payload), number(job.attempts), Json.string(why), number(now)])
    if moved.is_err() then
      return Result<bool, Error>.Err(moved.unwrap_err())
    end
    self.done(job)
  end

  public fun pending(self) -> Result<int, Error>
    let rows = self.db.query("SELECT COUNT(*) AS n FROM {self.table}", [])
    if rows.is_err() then
      return Result<int, Error>.Err(rows.unwrap_err())
    end
    Result<int, Error>.Ok(rows.unwrap()[0].get("n", Json.null()).as_number() as int)
  end

  public fun failed(self) -> Result<array<FailedJob>, Error>
    let rows = self.db.query("SELECT id, kind, payload, attempts, error FROM {self.table}_failed ORDER BY id ASC", [])
    if rows.is_err() then
      return Result<array<FailedJob>, Error>.Err(rows.unwrap_err())
    end
    let out: array<FailedJob> = []
    for row in rows.unwrap() do
      out.push(FailedJob { id: "{row.get("id", Json.null()).as_number() as int}", kind: row.get("kind", Json.null()).as_string(), payload: row.get("payload", Json.null()).as_string(), attempts: row.get("attempts", Json.null()).as_number() as int, error: row.get("error", Json.null()).as_string() })
    end
    Result<array<FailedJob>, Error>.Ok(out)
  end

  public fun retry_failed(self, id: string, now: int) -> Result<bool, Error>
    let n = Json.number((int.parse(id) ?? 0) as float)
    let rows = self.db.query("SELECT kind, payload FROM {self.table}_failed WHERE id = ?", [n])
    if rows.is_err() then
      return Result<bool, Error>.Err(rows.unwrap_err())
    end
    let found = rows.unwrap()
    if found.is_empty() then
      return Result<bool, Error>.Ok(false)
    end
    let again = self.db.execute("INSERT INTO {self.table} (kind, payload, attempts, available_at, created_at) VALUES (?, ?, 0, ?, ?)", [found[0].get("kind", Json.null()), found[0].get("payload", Json.null()), number(now), number(now)])
    if again.is_err() then
      return Result<bool, Error>.Err(again.unwrap_err())
    end
    self.forget_failed(id)
  end

  public fun forget_failed(self, id: string) -> Result<bool, Error>
    let gone = self.db.execute("DELETE FROM {self.table}_failed WHERE id = ?", [Json.number((int.parse(id) ?? 0) as float)])
    if gone.is_err() then
      return Result<bool, Error>.Err(gone.unwrap_err())
    end
    Result<bool, Error>.Ok(gone.unwrap() > 0)
  end
end

-- Moves the jobs that are due from the delayed set to the list, and the ones whose reservation ran
-- out from the reserved set to the list; then takes the first job of the list, reserves it
-- (counting the attempt) and gives it. All in one step, so two workers never take the same job.
-- KEYS: list, delayed, reserved, notify. ARGV: now, the time the reservation ends.
const CLAIM = "local due = redis.call('ZRANGEBYSCORE', KEYS[2], '-inf', ARGV[1], 'LIMIT', 0, 100)
for _, job in ipairs(due) do
  redis.call('ZREM', KEYS[2], job)
  redis.call('RPUSH', KEYS[1], job)
end
local lost = redis.call('ZRANGEBYSCORE', KEYS[3], '-inf', ARGV[1], 'LIMIT', 0, 100)
for _, job in ipairs(lost) do
  redis.call('ZREM', KEYS[3], job)
  redis.call('RPUSH', KEYS[1], job)
end
local job = redis.call('LPOP', KEYS[1])
if not job then
  return false
end
redis.call('LPOP', KEYS[4])
local data = cjson.decode(job)
data['attempts'] = data['attempts'] + 1
local taken = cjson.encode(data)
redis.call('ZADD', KEYS[3], ARGV[2], taken)
return taken"

--" The jobs in Redis, like Laravel's Redis queue: the ready jobs are a list, the delayed ones and the
running ones sorted sets (by the time they are due, by the time their reservation ends), and a worker
with nothing to do waits on a list that every push writes to, so a new job is picked up at once. --"
struct RedisDriver
  public redis: Redis
  --" The name of the queue; the keys are `queues:{name}`, `queues:{name}:delayed`... --"
  public name: string
end

impl RedisDriver
  fun key(self, part: string) -> string
    if part == "" then "queues:{self.name}" else "queues:{self.name}:{part}" end
  end

  fun take(self, now: int, timeout: int) -> Result<JobRow?, Error>
    let r = self.redis.eval(CLAIM, [self.key(""), self.key("delayed"), self.key("reserved"), self.key("notify")], ["{now}", "{now + timeout * 1000}"])
    if r.is_err() then
      return Result<JobRow?, Error>.Err(r.unwrap_err())
    end
    let j = r.unwrap()
    if not j.is_string() then
      return Result<JobRow?, Error>.Ok(none)
    end
    let parsed = Json.parse(j.as_string())
    if parsed.is_err() then
      return Result<JobRow?, Error>.Err(parsed.unwrap_err())
    end
    let d = parsed.unwrap()
    let row = JobRow {
      id: (d.get("id") ?? Json.string("?")).as_string(),
      kind: (d.get("kind") ?? Json.string("")).as_string(),
      payload: (d.get("payload") ?? Json.string("")).as_string(),
      attempts: (d.get("attempts") ?? Json.number(1.0)).as_number() as int,
      token: j.as_string(),
    }
    Result<JobRow?, Error>.Ok(row)
  end

  fun failed_records(self) -> Result<array<string>, Error>
    self.redis.lrange(self.key("failed"), 0, -1)
  end

  --" The text of the failed record with this id, or `none`. --"
  fun find_failed(self, id: string) -> Result<string?, Error>
    let all = self.failed_records()
    if all.is_err() then
      return Result<string?, Error>.Err(all.unwrap_err())
    end
    for text in all.unwrap() do
      let parsed = Json.parse(text)
      if parsed.is_ok() and (parsed.unwrap().get("id") ?? Json.null()).is_string() and (parsed.unwrap().get("id") ?? Json.null()).as_string() == id then
        return Result<string?, Error>.Ok(text)
      end
    end
    Result<string?, Error>.Ok(none)
  end
end

impl QueueDriver for RedisDriver
  public fun install(self) -> Result<bool, Error>
    let pong = self.redis.command(["PING"])
    if pong.is_err() then
      return Result<bool, Error>.Err(pong.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  public fun waits(self) -> bool
    true
  end

  public fun push(self, kind: string, payload: string, available_at: int, now: int) -> Result<bool, Error>
    let id = Crypto.token(9)
    let job = Json.object({"id": Json.string(if id.is_ok() then id.unwrap() else "{now}" end), "kind": Json.string(kind), "payload": Json.string(payload), "attempts": number(0)}).to_text()
    if available_at > now then
      let r = self.redis.zadd(self.key("delayed"), available_at as float, job)
      if r.is_err() then
        return Result<bool, Error>.Err(r.unwrap_err())
      end
      return Result<bool, Error>.Ok(true)
    end
    let r = self.redis.rpush(self.key(""), job)
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    self.redis.rpush(self.key("notify"), "1")
    Result<bool, Error>.Ok(true)
  end

  public fun claim(self, now: int, timeout: int, wait: int) -> Result<JobRow?, Error>
    let first = self.take(now, timeout)
    if first.is_err() or first.unwrap() != none or wait <= 0 then
      return first
    end
    -- nothing is due: wait for a push to write in the notify list, then look again
    let woken = self.redis.blpop([self.key("notify")], wait)
    if woken.is_err() then
      return Result<JobRow?, Error>.Err(woken.unwrap_err())
    end
    if woken.unwrap() == none then
      return Result<JobRow?, Error>.Ok(none)
    end
    self.take(now + wait * 1000, timeout)
  end

  public fun done(self, job: JobRow) -> Result<bool, Error>
    let r = self.redis.zrem(self.key("reserved"), job.token)
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  public fun release(self, job: JobRow, available_at: int, why: string) -> Result<bool, Error>
    let gone = self.redis.zrem(self.key("reserved"), job.token)
    if gone.is_err() then
      return Result<bool, Error>.Err(gone.unwrap_err())
    end
    let later = self.redis.zadd(self.key("delayed"), available_at as float, job.token)
    if later.is_err() then
      return Result<bool, Error>.Err(later.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  public fun fail(self, job: JobRow, why: string, now: int) -> Result<bool, Error>
    let record = Json.object({"id": Json.string(job.id), "kind": Json.string(job.kind), "payload": Json.string(job.payload), "attempts": number(job.attempts), "error": Json.string(why), "failed_at": number(now)}).to_text()
    let saved = self.redis.rpush(self.key("failed"), record)
    if saved.is_err() then
      return Result<bool, Error>.Err(saved.unwrap_err())
    end
    self.done(job)
  end

  public fun pending(self) -> Result<int, Error>
    let ready = self.redis.llen(self.key(""))
    let later = self.redis.zcard(self.key("delayed"))
    let running = self.redis.zcard(self.key("reserved"))
    if ready.is_err() or later.is_err() or running.is_err() then
      return queue_error<int>("Redis: the size of the queue could not be read")
    end
    Result<int, Error>.Ok(ready.unwrap() + later.unwrap() + running.unwrap())
  end

  public fun failed(self) -> Result<array<FailedJob>, Error>
    let all = self.failed_records()
    if all.is_err() then
      return Result<array<FailedJob>, Error>.Err(all.unwrap_err())
    end
    let out: array<FailedJob> = []
    for text in all.unwrap() do
      let parsed = Json.parse(text)
      if parsed.is_err() then
        continue
      end
      let d = parsed.unwrap()
      out.push(FailedJob { id: (d.get("id") ?? Json.string("?")).as_string(), kind: (d.get("kind") ?? Json.string("")).as_string(), payload: (d.get("payload") ?? Json.string("")).as_string(), attempts: (d.get("attempts") ?? Json.number(0.0)).as_number() as int, error: (d.get("error") ?? Json.string("")).as_string() })
    end
    Result<array<FailedJob>, Error>.Ok(out)
  end

  public fun retry_failed(self, id: string, now: int) -> Result<bool, Error>
    let found = self.find_failed(id)
    if found.is_err() then
      return Result<bool, Error>.Err(found.unwrap_err())
    end
    let text = found.unwrap()
    if text == none then
      return Result<bool, Error>.Ok(false)
    end
    let d = Json.parse(text).unwrap()
    let kind = (d.get("kind") ?? Json.string("")).as_string()
    let payload = (d.get("payload") ?? Json.string("")).as_string()
    let again = self.push(kind, payload, now, now)
    if again.is_err() then
      return Result<bool, Error>.Err(again.unwrap_err())
    end
    self.forget_failed(id)
  end

  public fun forget_failed(self, id: string) -> Result<bool, Error>
    let found = self.find_failed(id)
    if found.is_err() then
      return Result<bool, Error>.Err(found.unwrap_err())
    end
    let text = found.unwrap()
    if text == none then
      return Result<bool, Error>.Ok(false)
    end
    let r = self.redis.command(["LREM", self.key("failed"), "1", text])
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end
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

--" The queue and its handlers. --"
struct Queue
  public driver: QueueDriver
  public max_attempts: int
  --" Seconds after which a job that is still marked as running is given to another worker. --"
  public timeout: int
  --" With Redis: seconds a worker waits for a new job before it looks again. --"
  public wait: int
  --" The time in milliseconds; tests give their own. --"
  public clock: fun() -> int
  handlers: map<string, fun(Json) -> string?>
end

impl Queue
  --" A queue in `db`; `dialect` is `"sqlite"`, `"postgres"` or `"mysql"` (it only changes how the tables
  are made). --"
  public fun new(db: Db, dialect: string) -> Queue
    Queue.with(DbDriver { db: db, dialect: dialect, table: "jobs" })
  end

  --" A queue in Redis, under the name `name` (`"default"`). --"
  public fun redis(redis: Redis, name: string) -> Queue
    Queue.with(RedisDriver { redis: redis, name: name })
  end

  --" A queue on a driver of your own. --"
  public fun with(driver: QueueDriver) -> Queue
    Queue { driver: driver, max_attempts: 3, timeout: 300, wait: 5, clock: fun() -> int time.now() end, handlers: {} }
  end

  --" Makes the tables if they do not exist (checks the connection with Redis). --"
  public fun install(self) -> Result<bool, Error>
    self.driver.install()
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
    self.driver.push(Reflect.type_name<T>(), Json.of(job).to_text(), now + seconds * 1000, now)
  end

  --" How many jobs wait (or run). --"
  public fun pending(self) -> Result<int, Error>
    self.driver.pending()
  end

  fun run(self, wait: int) -> Result<bool, Error>
    let claimed = self.driver.claim(self.clock(), self.timeout, wait)
    if claimed.is_err() then
      return Result<bool, Error>.Err(claimed.unwrap_err())
    end
    let job = claimed.unwrap()
    if job == none then
      return Result<bool, Error>.Ok(false)
    end
    let handler = self.handlers[job.kind]
    if handler == none then
      Log.error("job {job.id}: no handler for {job.kind}")
      let gave = self.driver.fail(job, "no handler for {job.kind}", self.clock())
      if gave.is_err() then
        return Result<bool, Error>.Err(gave.unwrap_err())
      end
      return Result<bool, Error>.Ok(true)
    end
    let payload = Json.parse(job.payload)
    if payload.is_err() then
      let gave = self.driver.fail(job, "the payload is not JSON", self.clock())
      if gave.is_err() then
        return Result<bool, Error>.Err(gave.unwrap_err())
      end
      return Result<bool, Error>.Ok(true)
    end
    let why = handler(payload.unwrap())
    if why == none then
      let done = self.driver.done(job)
      if done.is_err() then
        return Result<bool, Error>.Err(done.unwrap_err())
      end
      return Result<bool, Error>.Ok(true)
    end
    Log.warn("job {job.id} ({job.kind}) failed, attempt {job.attempts}: {why}")
    if job.attempts >= self.max_attempts then
      let gave = self.driver.fail(job, why, self.clock())
      if gave.is_err() then
        return Result<bool, Error>.Err(gave.unwrap_err())
      end
      Log.error("job {job.id} ({job.kind}) gave up after {job.attempts} attempts")
      return Result<bool, Error>.Ok(true)
    end
    let kept = self.driver.release(job, self.clock() + backoff(job.attempts) * 1000, why)
    if kept.is_err() then
      return Result<bool, Error>.Err(kept.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" Does the next due job. Gives `true` when there was one (done or failed), `false` when none was due. --"
  public fun work_one(self) -> Result<bool, Error>
    self.run(0)
  end

  --" Does the due jobs. With `once`, ends when none is due; otherwise it waits for new ones and never
  returns (with Redis the wait is on the queue itself, so a new job starts at once; with a
  database the worker looks again every second). A database error ends it with that error. --"
  public fun work(self, once: bool) -> Result<int, Error>
    let done = 0
    while true do
      let turn = self.run(if once then 0 else self.wait end)
      if turn.is_err() then
        return Result<int, Error>.Err(turn.unwrap_err())
      end
      if turn.unwrap() then
        done += 1
      else
        if once then
          return Result<int, Error>.Ok(done)
        end
        if not self.driver.waits() then
          time.sleep(1000)
        end
      end
    end
    Result<int, Error>.Ok(done)
  end

  --" The jobs that gave up, oldest first. --"
  public fun failed(self) -> Result<array<FailedJob>, Error>
    self.driver.failed()
  end

  --" Puts a failed job back in the queue, with a fresh count of attempts. `false` if there is none with this id. --"
  public fun retry_failed(self, id: string) -> Result<bool, Error>
    self.driver.retry_failed(id, self.clock())
  end

  --" Deletes a failed job. `false` if there is none with this id. --"
  public fun forget_failed(self, id: string) -> Result<bool, Error>
    self.driver.forget_failed(id)
  end
end

export Queue, QueueDriver, DbDriver, RedisDriver, JobRow, FailedJob

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

A job structure may carry `#[Retry(tries: 5, backoff: [10, 60])]`, `#[Unique(seconds: 3600)]` and `#[Delay(seconds: 30)]`;
`queue.use(...)` and `queue.handle_with<T>(...)` add middleware (`rate_limited`, `without_overlapping`); and
`work` leaves cleanly when the process is told to stop (`Process.stopping()`), after the job it is doing.

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

import "web/cache.q" as cc

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
  --" The queue it came from (`"default"` unless you added others with `Queue.lane`). --"
  public queue: string = "default"
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
  --" Puts a running job back for later **without counting the attempt** (a middleware asked to wait). --"
  fun requeue(self, job: JobRow, available_at: int) -> Result<bool, Error>
  --" Takes the lock of a unique job; `false` when somebody holds it. It ends by itself after `seconds`. --"
  fun lock(self, key: string, seconds: int, now: int) -> Result<bool, Error>
  fun unlock(self, key: string) -> Result<bool, Error>
  fun pending(self) -> Result<int, Error>
  fun failed(self) -> Result<array<FailedJob>, Error>
  fun retry_failed(self, id: string, now: int) -> Result<bool, Error>
  fun forget_failed(self, id: string) -> Result<bool, Error>
  --" Starts a counter at `n` (a batch of `n` jobs). It is forgotten after `seconds` if nobody ends it. --"
  fun countdown_start(self, key: string, n: int, seconds: int, now: int) -> Result<bool, Error>
  --" Takes one off the counter; `true` for the **one** call that brings it to zero, whatever the number of workers. --"
  fun countdown(self, key: string) -> Result<bool, Error>
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
    let locks = self.db.execute("CREATE TABLE IF NOT EXISTS {self.table}_locks (lock_key VARCHAR(190) PRIMARY KEY, expires_at BIGINT NOT NULL)", [])
    if locks.is_err() then
      return Result<bool, Error>.Err(locks.unwrap_err())
    end
    let counts = self.db.execute("CREATE TABLE IF NOT EXISTS {self.table}_counts (count_key VARCHAR(190) PRIMARY KEY, n BIGINT NOT NULL, expires_at BIGINT NOT NULL)", [])
    if counts.is_err() then
      return Result<bool, Error>.Err(counts.unwrap_err())
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

  public fun requeue(self, job: JobRow, available_at: int) -> Result<bool, Error>
    let kept = self.db.execute("UPDATE {self.table} SET reserved_at = NULL, available_at = ?, attempts = attempts - 1 WHERE id = ?", [number(available_at), Json.number((int.parse(job.id) ?? 0) as float)])
    if kept.is_err() then
      return Result<bool, Error>.Err(kept.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  public fun lock(self, key: string, seconds: int, now: int) -> Result<bool, Error>
    let old = self.db.execute("DELETE FROM {self.table}_locks WHERE expires_at <= ?", [number(now)])
    if old.is_err() then
      return Result<bool, Error>.Err(old.unwrap_err())
    end
    let taken = self.db.execute("INSERT INTO {self.table}_locks (lock_key, expires_at) VALUES (?, ?)", [Json.string(key), number(now + seconds * 1000)])
    if taken.is_ok() then
      return Result<bool, Error>.Ok(true)
    end
    let why = taken.unwrap_err().message.lower()
    if why.contains("unique") or why.contains("duplicate") or why.contains("constraint") or why.contains("primary") then
      return Result<bool, Error>.Ok(false)
    end
    Result<bool, Error>.Err(taken.unwrap_err())
  end

  public fun unlock(self, key: string) -> Result<bool, Error>
    let gone = self.db.execute("DELETE FROM {self.table}_locks WHERE lock_key = ?", [Json.string(key)])
    if gone.is_err() then
      return Result<bool, Error>.Err(gone.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
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

  public fun countdown_start(self, key: string, n: int, seconds: int, now: int) -> Result<bool, Error>
    let old = self.db.execute("DELETE FROM {self.table}_counts WHERE expires_at <= ?", [number(now)])
    if old.is_err() then
      return Result<bool, Error>.Err(old.unwrap_err())
    end
    let made = self.db.execute("INSERT INTO {self.table}_counts (count_key, n, expires_at) VALUES (?, ?, ?)", [Json.string(key), number(n), number(now + seconds * 1000)])
    if made.is_err() then
      return Result<bool, Error>.Err(made.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  public fun countdown(self, key: string) -> Result<bool, Error>
    let down = self.db.execute("UPDATE {self.table}_counts SET n = n - 1 WHERE count_key = ?", [Json.string(key)])
    if down.is_err() then
      return Result<bool, Error>.Err(down.unwrap_err())
    end
    -- the call that removes the row is the last one: two workers cannot both delete it
    let last = self.db.execute("DELETE FROM {self.table}_counts WHERE count_key = ? AND n <= 0", [Json.string(key)])
    if last.is_err() then
      return Result<bool, Error>.Err(last.unwrap_err())
    end
    Result<bool, Error>.Ok(last.unwrap() == 1)
  end
end

-- Moves the jobs that are due from the delayed set to the list, and the ones whose reservation ran
-- out from the reserved set to the list; then takes the first job of the list, reserves it
-- (counting the attempt) and gives it. All in one item, so two workers never take the same job.
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

  public fun requeue(self, job: JobRow, available_at: int) -> Result<bool, Error>
    let parsed = Json.parse(job.token)
    if parsed.is_err() then
      return Result<bool, Error>.Err(parsed.unwrap_err())
    end
    let d = parsed.unwrap()
    let fields: map<string, Json> = {}
    for k in d.as_object().keys() do
      fields[k] = d.get(k) ?? Json.null()
    end
    fields["attempts"] = number(job.attempts - 1)
    let gone = self.redis.zrem(self.key("reserved"), job.token)
    if gone.is_err() then
      return Result<bool, Error>.Err(gone.unwrap_err())
    end
    let later = self.redis.zadd(self.key("delayed"), available_at as float, Json.object(fields).to_text())
    if later.is_err() then
      return Result<bool, Error>.Err(later.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  public fun lock(self, key: string, seconds: int, now: int) -> Result<bool, Error>
    self.redis.set_if_absent("{self.key("locks")}:{key}", "1", seconds)
  end

  public fun unlock(self, key: string) -> Result<bool, Error>
    let r = self.redis.del("{self.key("locks")}:{key}")
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
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

  public fun countdown_start(self, key: string, n: int, seconds: int, now: int) -> Result<bool, Error>
    let r = self.redis.set_ex("{self.key("counts")}:{key}", "{n}", seconds)
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  public fun countdown(self, key: string) -> Result<bool, Error>
    let r = self.redis.command(["DECR", "{self.key("counts")}:{key}"])
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    -- DECR is atomic: one call sees zero
    let left = r.unwrap()
    if left.is_number() and left.as_number() as int == 0 then
      self.redis.del("{self.key("counts")}:{key}")
      return Result<bool, Error>.Ok(true)
    end
    Result<bool, Error>.Ok(false)
  end
end

--" What a job does for the queue: `done`, `failed` (it will be tried again, or abandoned after the last
attempt) or `released` (it waits, and the attempt is **not** counted: a middleware that says "not now"). --"
struct Outcome
  public status: string
  public why: string = ""
  public delay: int = 0
end

impl Outcome
  public fun done() -> Outcome
    Outcome { status: "done" }
  end

  public fun failed(why: string) -> Outcome
    Outcome { status: "failed", why: why }
  end

  --" Wait `seconds`, then try again without using an attempt. --"
  public fun release(seconds: int) -> Outcome
    Outcome { status: "released", delay: seconds }
  end
end

--" The job that a middleware sees. --"
struct Job
  public id: string
  public kind: string
  public attempts: int
  public payload: string
end

type JobNext = fun() -> Outcome

--" Code around a job: it may run it (`next()`), skip it, or give it back (`Outcome.release(10)`). The
first added is the outermost. --"
type JobMiddleware = fun(Job, JobNext) -> Outcome

--" `#[Retry(tries: 5, backoff: [10, 60, 300])]` on a job structure: how many times it is tried (3 by
default), and the seconds to wait before attempt 2, 3...; the last number is used for the next ones. --"
#[annotation]
struct Retry
  tries: int = 0
  backoff: array<int> = []
end

--" `#[Unique(seconds: 3600)]` on a job structure: while a job with the same fields waits or runs (at
most `seconds`), pushing it again does nothing (`push` gives `false`). --"
#[annotation]
struct Unique
  seconds: int = 3600
end

--" `#[Delay(seconds: 30)]` on a job structure: it starts that long after it is pushed, unless `push_in`
says otherwise. --"
#[annotation]
struct Delay
  seconds: int
end

--" `#[OnQueue(name: high)]` on a job structure: the queue it goes to when `push` is used (see `Queue.lane`). --"
#[annotation]
struct OnQueue
  name: string
end

--" What the annotations of a job structure say. --"
struct Settings
  public tries: int
  public backoff: array<int>
  public unique: int
  public delay: int
  public lane: string
end

fun settings_of<T>() -> Settings
  let info = Reflect.struct_info<T>()
  let tries = 0
  let backoff: array<int> = []
  let unique = 0
  let delay = 0
  let lane = "default"
  let on = info.annotation("OnQueue")
  if on != none then
    lane = on.get_string("name") ?? "default"
  end
  let retry = info.annotation("Retry")
  if retry != none then
    tries = retry.get_int("tries") ?? 0
    let list = retry.args["backoff"]
    if list != none and list.is_array() then
      for x in list.as_array() do
        if x.is_number() then
          backoff.push(x.as_number() as int)
        end
      end
    end
  end
  let u = info.annotation("Unique")
  if u != none then
    unique = u.get_int("seconds") ?? 3600
  end
  let d = info.annotation("Delay")
  if d != none then
    delay = d.get_int("seconds") ?? 0
  end
  Settings { tries: tries, backoff: backoff, unique: unique, delay: delay, lane: lane }
end

--" Seconds to wait before attempt number `attempt + 1`, when the job has no `backoff` of its own. --"
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

--" What `work_with` does. --"
struct WorkOptions
  --" Stop when no job is due (instead of waiting for new ones). --"
  public once: bool = false
  --" Stop after this many jobs (0: no limit): a worker that restarts often keeps its memory small. --"
  public max_jobs: int = 0
  --" Stop after this many seconds (0: no limit), at the end of the job that is running. --"
  public max_seconds: int = 0
  --" With a database: how long to wait between two looks when nothing is due. --"
  public sleep_ms: int = 1000
  --" The queues to serve, the most important first (`["high", "default"]`); none: all of them, in the order they were added. --"
  public queues: array<string> = []
end

--" A job written down for later: where it goes, its type and its fields (as text). --"
struct Step
  public queue: string
  public kind: string
  public payload: string
  public unique: int = 0
  public delay: int = 0
end

-- What travels with a job of a chain or a batch, around its own payload.
struct Meta
  public chain: array<Step> = []
  public batch: string = ""
  public then_job: array<Step> = []
  public catch_job: array<Step> = []
end

struct Envelope
  #[JsonName("_q")]
  public meta: Meta
  public job: string
end

struct Opened
  public meta: Meta
  public payload: string
end

fun open_payload(text: string) -> Opened
  let none_meta = Meta { chain: [], batch: "", then_job: [], catch_job: [] }
  let parsed = Json.parse(text)
  if parsed.is_err() or not parsed.unwrap().is_object() or parsed.unwrap().get("_q") == none then
    return Opened { meta: none_meta, payload: text }
  end
  let read = Json.to<Envelope>(parsed.unwrap())
  if read.is_err() then
    return Opened { meta: none_meta, payload: text }
  end
  Opened { meta: read.unwrap().meta, payload: read.unwrap().job }
end

--" The queue and its handlers. --"
struct Queue
  public driver: QueueDriver
  --" Tries for a job that has no `#[Retry]`. --"
  public max_attempts: int
  --" Seconds after which a job that is still marked as running is given to another worker. --"
  public timeout: int
  --" With Redis: seconds a worker waits for a new job before it looks again (and checks for a stop order). --"
  public wait: int
  --" The time in milliseconds; tests give their own. --"
  public clock: fun() -> int
  handlers: map<string, fun(Job) -> Outcome>
  settings: map<string, Settings>
  middlewares: array<JobMiddleware>
  lanes: array<string>
  drivers: map<string, QueueDriver>
end

fun lock_key(kind: string, payload: string) -> string
  "{kind}:{Hash.sha256(payload)}"
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
    Queue { driver: driver, max_attempts: 3, timeout: 300, wait: 2, clock: fun() -> int time.now() end, handlers: {}, settings: {}, middlewares: [], lanes: ["default"], drivers: {"default": driver} }
  end

  --" Makes the tables if they do not exist (checks the connection with Redis). --"
  public fun install(self) -> Result<bool, Error>
    for name in self.lanes do
      let made = self.driver_of(name).install()
      if made.is_err() then
        return made
      end
    end
    Result<bool, Error>.Ok(true)
  end

  --" Code around **every** job (see `JobMiddleware`); the first added is the outermost. --"
  public fun use(self, m: JobMiddleware)
    self.middlewares.push(m)
  end

  --" Says what to do with the jobs of type `T`: `none` when it is done, otherwise why it failed. The
  annotations of `T` (`#[Retry]`, `#[Unique]`, `#[Delay]`) say how it is tried. --"
  public fun handle<T>(self, handler: fun(T) -> string?)
    self.handle_with<T>(handler, [])
  end

  --" Like `handle`, with middleware for this type of job only (inside the global ones). --"
  public fun handle_with<T>(self, handler: fun(T) -> string?, around: array<JobMiddleware>)
    let kind = Reflect.type_name<T>()
    self.settings[kind] = settings_of<T>()
    let all: array<JobMiddleware> = []
    for m in self.middlewares do
      all.push(m)
    end
    for m in around do
      all.push(m)
    end
    self.handlers[kind] = fun(job: Job) -> Outcome
      let payload = Json.parse(open_payload(job.payload).payload)
      if payload.is_err() then
        return Outcome.failed("the payload is not JSON")
      end
      let read = Json.to<T>(payload.unwrap())
      if read.is_err() then
        return Outcome.failed("the job cannot be read: {read.unwrap_err().message}")
      end
      let value = read.unwrap()
      let core: JobNext = fun() -> Outcome
        let why = handler(value)
        if why == none then Outcome.done() else Outcome.failed(why) end
      end
      -- the first middleware is the outermost
      let chain = core
      let i = all.len() - 1
      while i >= 0 do
        let m = all[i]
        let inner = chain
        chain = fun() -> Outcome m(job, inner) end
        i -= 1
      end
      chain()
    end
  end

  --" Adds a queue next to `"default"`: `queue.lane("high", DbDriver { db: db, dialect: "sqlite", table: "jobs_high" })`
  or `queue.lane("high", RedisDriver { redis: redis, name: "high" })`. A worker serves the queues in the order
  of `WorkOptions.queues`, so the jobs of an earlier one always go first. --"
  public fun lane(self, name: string, driver: QueueDriver)
    if self.drivers[name] == none then
      self.lanes.push(name)
    end
    self.drivers[name] = driver
  end

  fun driver_of(self, name: string) -> QueueDriver
    self.drivers[name] ?? self.driver
  end

  --" Writes a job down, to be done as soon as a worker is free (or after its `#[Delay]`), in the queue its
  `#[OnQueue]` names (`"default"`). Gives `false` when a `#[Unique]` job like it is already there. --"
  public fun push<T>(self, job: T) -> Result<bool, Error>
    self.send(step_of<T>(job), none, -1)
  end

  --" Writes a job down, to be done after `seconds`. --"
  public fun push_in<T>(self, job: T, seconds: int) -> Result<bool, Error>
    self.send(step_of<T>(job), none, seconds)
  end

  --" Writes a job down in the queue `lane`, whatever its `#[OnQueue]` says. --"
  public fun push_on<T>(self, lane: string, job: T) -> Result<bool, Error>
    let item = step_of<T>(job)
    item.queue = lane
    self.send(item, none, -1)
  end

  --" Writes a item down; `seconds` below zero: the delay of the item. --"
  public fun send(self, item: Step, meta: Meta?, seconds: int) -> Result<bool, Error>
    let now = self.clock()
    let d = self.driver_of(item.queue)
    let payload = if meta == none then item.payload else Json.of(Envelope { meta: meta, job: item.payload }).to_text() end
    if item.unique > 0 then
      let taken = d.lock(lock_key(item.kind, item.payload), item.unique, now)
      if taken.is_err() then
        return Result<bool, Error>.Err(taken.unwrap_err())
      end
      if not taken.unwrap() then
        return Result<bool, Error>.Ok(false)
      end
    end
    let wait_for = if seconds < 0 then item.delay else seconds end
    d.push(item.kind, payload, now + wait_for * 1000, now)
  end

  --" A chain of jobs: each starts when the one before it is done, and none starts if one gives up. --"
  public fun chain(self) -> Chain
    Chain { queue: self, steps: [], fails: [] }
  end

  --" A batch of jobs, done in parallel; one more job can follow when all are done, one when a job gives up. --"
  public fun batch(self) -> Batch
    Batch { queue: self, steps: [], after: [], fails: [] }
  end

  --" How many jobs wait (or run), in every queue. --"
  public fun pending(self) -> Result<int, Error>
    let total = 0
    for name in self.lanes do
      let n = self.driver_of(name).pending()
      if n.is_err() then
        return n
      end
      total += n.unwrap()
    end
    Result<int, Error>.Ok(total)
  end

  fun finished(self, d: QueueDriver, job: JobRow)
    let s = self.settings[job.kind]
    if s != none and s.unique > 0 then
      d.unlock(lock_key(job.kind, open_payload(job.payload).payload))
    end
  end

  fun give_up(self, d: QueueDriver, job: JobRow, why: string) -> Result<bool, Error>
    let gave = d.fail(job, why, self.clock())
    self.finished(d, job)
    let meta = open_payload(job.payload).meta
    if not meta.catch_job.is_empty() then
      -- a batch tells its failure once, however many of its jobs give up
      let first = true
      if meta.batch != "" then
        let got = self.driver.lock("caught:{meta.batch}", 86400, self.clock())
        first = got.is_ok() and got.unwrap()
      end
      if first then
        for item in meta.catch_job do
          self.send(item, none, -1)
        end
      end
    end
    gave
  end

  -- What follows a job that is done: the next of its chain, the end of its batch.
  fun advance(self, job: JobRow)
    let meta = open_payload(job.payload).meta
    if meta.batch != "" then
      let last = self.driver.countdown("batch:{meta.batch}")
      if last.is_ok() and last.unwrap() then
        for item in meta.then_job do
          self.send(item, none, -1)
        end
      end
    end
    if not meta.chain.is_empty() then
      let rest: array<Step> = []
      let i = 1
      while i < meta.chain.len() do
        rest.push(meta.chain[i])
        i += 1
      end
      self.send(meta.chain[0], Meta { chain: rest, batch: "", then_job: [], catch_job: meta.catch_job }, -1)
    end
  end

  fun run(self, wait: int, order: array<string>) -> Result<bool, Error>
    for name in order do
      let d = self.driver_of(name)
      let claimed = d.claim(self.clock(), self.timeout, if order.len() == 1 then wait else 0 end)
      if claimed.is_err() then
        return Result<bool, Error>.Err(claimed.unwrap_err())
      end
      let job = claimed.unwrap()
      if job != none then
        return self.perform(d, job)
      end
    end
    Result<bool, Error>.Ok(false)
  end

  fun perform(self, d: QueueDriver, job: JobRow) -> Result<bool, Error>
    let handler = self.handlers[job.kind]
    if handler == none then
      Log.error("job {job.id}: no handler for {job.kind}")
      let gave = self.give_up(d, job, "no handler for {job.kind}")
      if gave.is_err() then
        return Result<bool, Error>.Err(gave.unwrap_err())
      end
      return Result<bool, Error>.Ok(true)
    end
    let outcome = handler(Job { id: job.id, kind: job.kind, attempts: job.attempts, payload: open_payload(job.payload).payload })
    if outcome.status == "done" then
      let done = d.done(job)
      self.finished(d, job)
      if done.is_err() then
        return Result<bool, Error>.Err(done.unwrap_err())
      end
      self.advance(job)
      return Result<bool, Error>.Ok(true)
    end
    if outcome.status == "released" then
      let kept = d.requeue(job, self.clock() + outcome.delay * 1000)
      if kept.is_err() then
        return Result<bool, Error>.Err(kept.unwrap_err())
      end
      return Result<bool, Error>.Ok(true)
    end
    Log.warning("job {job.id} ({job.kind}) failed, attempt {job.attempts}: {outcome.why}")
    let s = self.settings[job.kind]
    let tries = if s != none and s.tries > 0 then s.tries else self.max_attempts end
    if job.attempts >= tries then
      let gave = self.give_up(d, job, outcome.why)
      if gave.is_err() then
        return Result<bool, Error>.Err(gave.unwrap_err())
      end
      Log.error("job {job.id} ({job.kind}) gave up after {job.attempts} attempts")
      return Result<bool, Error>.Ok(true)
    end
    let wait_for = if s != none and not s.backoff.is_empty() then s.backoff[if job.attempts - 1 < s.backoff.len() then job.attempts - 1 else s.backoff.len() - 1 end] else backoff(job.attempts) end
    let kept = d.release(job, self.clock() + wait_for * 1000, outcome.why)
    if kept.is_err() then
      return Result<bool, Error>.Err(kept.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" Does the next due job. Gives `true` when there was one (done or failed), `false` when none was due. --"
  public fun work_one(self) -> Result<bool, Error>
    self.run(0, self.lanes)
  end

  --" Does the due jobs. With `once`, ends when none is due; otherwise it waits for new ones. It also
  ends, at the end of the job that is running, when the process was told to stop (`Process.stopping()`). --"
  public fun work(self, once: bool) -> Result<int, Error>
    self.work_with(WorkOptions { once: once })
  end

  --" `work` with its limits: see `WorkOptions`. Gives how many jobs were done. With Redis the wait is
  on the queue itself, so a new job starts at once; with a database the worker looks again after
  `sleep_ms`. A worker that serves several queues looks at them in turn (at least every 250 ms with Redis).
  A database error ends it with that error. --"
  public fun work_with(self, o: WorkOptions) -> Result<int, Error>
    let order = if o.queues.is_empty() then self.lanes else o.queues end
    let waits = 0
    for name in order do
      if self.drivers[name] == none then
        return queue_error<int>("there is no queue called {name}")
      end
      if self.driver_of(name).waits() then
        waits += 1
      end
    end
    let nap = if order.len() > 1 and waits > 0 and o.sleep_ms > 250 then 250 else o.sleep_ms end
    let done = 0
    let started = time.now()
    while not Process.stopping() do
      if o.max_jobs > 0 and done >= o.max_jobs then
        break
      end
      if o.max_seconds > 0 and time.now() - started >= o.max_seconds * 1000 then
        break
      end
      let turn = self.run(if o.once then 0 else self.wait end, order)
      if turn.is_err() then
        return Result<int, Error>.Err(turn.unwrap_err())
      end
      if turn.unwrap() then
        done += 1
      else
        if o.once then
          break
        end
        if not (order.len() == 1 and waits == 1) then
          time.sleep(nap)
        end
      end
    end
    Result<int, Error>.Ok(done)
  end

  --" The jobs that gave up, oldest first, in every queue (`queue` says which). --"
  public fun failed(self) -> Result<array<FailedJob>, Error>
    let out: array<FailedJob> = []
    for name in self.lanes do
      let some = self.driver_of(name).failed()
      if some.is_err() then
        return some
      end
      for f in some.unwrap() do
        f.queue = name
        out.push(f)
      end
    end
    Result<array<FailedJob>, Error>.Ok(out)
  end

  --" Puts a failed job back in the queue, with a fresh count of attempts. `false` if there is none with this
  id (the queues are searched in order; `retry_failed_on` names one). --"
  public fun retry_failed(self, id: string) -> Result<bool, Error>
    for name in self.lanes do
      let again = self.retry_failed_on(name, id)
      if again.is_err() or again.unwrap() then
        return again
      end
    end
    Result<bool, Error>.Ok(false)
  end

  public fun retry_failed_on(self, lane: string, id: string) -> Result<bool, Error>
    self.driver_of(lane).retry_failed(id, self.clock())
  end

  --" Deletes a failed job. `false` if there is none with this id. --"
  public fun forget_failed(self, id: string) -> Result<bool, Error>
    for name in self.lanes do
      let gone = self.driver_of(name).forget_failed(id)
      if gone.is_err() or gone.unwrap() then
        return gone
      end
    end
    Result<bool, Error>.Ok(false)
  end
end

fun step_of<T>(job: T) -> Step
  let s = settings_of<T>()
  Step { queue: s.lane, kind: Reflect.type_name<T>(), payload: Json.of(job).to_text(), unique: s.unique, delay: s.delay }
end

--" Jobs that follow each other (`queue.chain()`). --"
struct Chain
  public queue: Queue
  public steps: array<Step>
  public fails: array<Step>
end

impl Chain
  --" The next job of the chain. --"
  public fun add<T>(self, job: T) -> Chain
    self.steps.push(step_of<T>(job))
    self
  end

  --" A job to push if one of the chain gives up. --"
  public fun on_failure<T>(self, job: T) -> Chain
    self.fails.push(step_of<T>(job))
    self
  end

  --" Pushes the first job. `false` when the chain is empty or the first job is a `#[Unique]` one already there. --"
  public fun dispatch(self) -> Result<bool, Error>
    if self.steps.is_empty() then
      return Result<bool, Error>.Ok(false)
    end
    let rest: array<Step> = []
    let i = 1
    while i < self.steps.len() do
      rest.push(self.steps[i])
      i += 1
    end
    self.queue.send(self.steps[0], Meta { chain: rest, batch: "", then_job: [], catch_job: self.fails }, -1)
  end
end

--" Jobs done in parallel (`queue.batch()`): `when_done` pushes a job when all are done, `when_failed` when one gives up
(once). The count is kept by the driver of the default queue, so any number of workers can finish them. --"
struct Batch
  public queue: Queue
  public steps: array<Step>
  public after: array<Step>
  public fails: array<Step>
end

impl Batch
  public fun add<T>(self, job: T) -> Batch
    self.steps.push(step_of<T>(job))
    self
  end

  --" The job to push when every job of the batch is done. --"
  public fun when_done<T>(self, job: T) -> Batch
    self.after.push(step_of<T>(job))
    self
  end

  --" The job to push, once, if a job of the batch gives up. --"
  public fun when_failed<T>(self, job: T) -> Batch
    self.fails.push(step_of<T>(job))
    self
  end

  --" Pushes the jobs and gives the id of the batch. --"
  public fun dispatch(self) -> Result<string, Error>
    let made = Crypto.token(9)
    let id = if made.is_ok() then made.unwrap() else "{self.queue.clock()}" end
    if self.steps.is_empty() then
      for item in self.after do
        self.queue.send(item, none, -1)
      end
      return Result<string, Error>.Ok(id)
    end
    let started = self.queue.driver.countdown_start("batch:{id}", self.steps.len(), 7 * 86400, self.queue.clock())
    if started.is_err() then
      return Result<string, Error>.Err(started.unwrap_err())
    end
    let meta = Meta { chain: [], batch: id, then_job: self.after, catch_job: self.fails }
    for item in self.steps do
      let sent = self.queue.send(item, meta, -1)
      if sent.is_err() then
        return Result<string, Error>.Err(sent.unwrap_err())
      end
    end
    Result<string, Error>.Ok(id)
  end
end

--" A middleware: at most `limit` jobs of the same key (by default their type) per `seconds`; the others wait
for the next window, without using an attempt. The count is in `cache`: with Redis it is exact for every
worker. --"
fun rate_limited(cache: cc.Cache, key: fun(Job) -> string, limit: int, seconds: int) -> JobMiddleware
  fun(job: Job, next: JobNext) -> Outcome
    let now = time.now()
    let window = now div (seconds * 1000)
    let seen = cache.increment("jobs-rate:{key(job)}@{window}", seconds * 2)
    if seen > limit then
      return Outcome.release(seconds - (now div 1000) mod seconds)
    end
    next()
  end
end

--" A middleware: two jobs with the same key never run together; the second waits `release_after` seconds,
without using an attempt. `expire_after` frees the key if a worker dies. --"
fun without_overlapping(cache: cc.Cache, key: fun(Job) -> string, expire_after: int, release_after: int) -> JobMiddleware
  fun(job: Job, next: JobNext) -> Outcome
    let name = "jobs-lock:{key(job)}"
    if cache.increment(name, expire_after) > 1 then
      return Outcome.release(release_after)
    end
    let out = next()
    cache.forget(name)
    out
  end
end

--" A key: the type of the job. --"
fun by_kind(job: Job) -> string
  job.kind
end

--" A key: the type and the fields of the job. --"
fun by_payload(job: Job) -> string
  "{job.kind}:{Hash.sha256(job.payload)}"
end

export Queue, QueueDriver, DbDriver, RedisDriver, JobRow, FailedJob, Job, Outcome, JobMiddleware, JobNext, WorkOptions, Retry, Unique, Delay, OnQueue, Settings, Chain, Batch, Step, rate_limited, without_overlapping, by_kind, by_payload

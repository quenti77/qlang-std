import "queue.q" as qq
import "web/cache.q" as cc

struct Mail
  public to: string
end

struct Resize
  public id: int
end

--" A queue with a clock the test moves by hand: `clock[0]` is the time in milliseconds. --"
fun fresh(clock: array<int>) -> qq.Queue
  let queue = qq.Queue.new(Db.connect("sqlite://:memory:").unwrap(), "sqlite")
  queue.clock = fun() -> int clock[0] end
  queue.install().unwrap()
  queue
end

fun test_a_job_is_done_by_the_handler_of_its_type_and_removed()
  let clock = [1000000]
  let queue = fresh(clock)
  let sent: array<string> = []
  queue.handle<Mail>(fun(m: Mail) -> string?
    sent.push(m.to)
    none
  end)
  queue.push(Mail { to: "ada@example.org" }).unwrap()
  assert_eq(queue.pending().unwrap(), 1)
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(sent, ["ada@example.org"])
  assert_eq(queue.pending().unwrap(), 0)
  assert_eq(queue.work_one().unwrap(), false)
end

fun test_jobs_are_done_in_order_and_work_once_stops_when_none_is_due()
  let clock = [1000000]
  let queue = fresh(clock)
  let order: array<int> = []
  queue.handle<Resize>(fun(r: Resize) -> string?
    order.push(r.id)
    none
  end)
  for i in 1..4 do
    queue.push(Resize { id: i }).unwrap()
  end
  assert_eq(queue.work(true).unwrap(), 3)
  assert_eq(order, [1, 2, 3])
end

fun test_a_delayed_job_waits_for_its_time()
  let clock = [1000000]
  let queue = fresh(clock)
  let ran: array<int> = []
  queue.handle<Resize>(fun(r: Resize) -> string?
    ran.push(r.id)
    none
  end)
  queue.push_in(Resize { id: 1 }, 60).unwrap()
  assert_eq(queue.work_one().unwrap(), false)
  clock[0] += 61000
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(ran, [1])
end

fun test_a_failing_job_is_tried_again_later_then_gives_up()
  let clock = [1000000]
  let queue = fresh(clock)
  let tries = [0]
  queue.handle<Mail>(fun(m: Mail) -> string?
    tries[0] += 1
    "smtp down"
  end)
  queue.push(Mail { to: "x" }).unwrap()
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(queue.work_one().unwrap(), false)
  assert_eq(queue.pending().unwrap(), 1)
  clock[0] += 11000
  assert_eq(queue.work_one().unwrap(), true)
  clock[0] += 61000
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(tries[0], 3)
  assert_eq(queue.pending().unwrap(), 0)
  let failed = queue.failed().unwrap()
  assert_eq(failed.len(), 1)
  assert_eq(failed[0].error, "smtp down")
  assert_eq(failed[0].attempts, 3)
end

fun test_a_failed_job_can_be_retried_or_forgotten()
  let clock = [1000000]
  let queue = fresh(clock)
  queue.max_attempts = 1
  let ok = [false]
  queue.handle<Mail>(fun(m: Mail) -> string? if ok[0] then none else "no" end end)
  queue.push(Mail { to: "x" }).unwrap()
  queue.work_one().unwrap()
  let id = queue.failed().unwrap()[0].id
  ok[0] = true
  assert_eq(queue.retry_failed(id).unwrap(), true)
  assert_eq(queue.failed().unwrap().len(), 0)
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(queue.pending().unwrap(), 0)
  assert_eq(queue.retry_failed("999").unwrap(), false)
  assert_eq(queue.forget_failed("999").unwrap(), false)
end

fun test_a_job_without_a_handler_goes_to_the_failed_table()
  let clock = [1000000]
  let queue = fresh(clock)
  queue.push(Mail { to: "x" }).unwrap()
  assert_eq(queue.work_one().unwrap(), true)
  assert(queue.failed().unwrap()[0].error.contains("no handler"))
end

fun test_a_job_left_running_by_a_dead_worker_is_given_again()
  let clock = [1000000]
  let db = Db.connect("sqlite://:memory:").unwrap()
  let queue = qq.Queue.new(db, "sqlite")
  queue.clock = fun() -> int clock[0] end
  queue.install().unwrap()
  let ran = [0]
  queue.handle<Mail>(fun(m: Mail) -> string?
    ran[0] += 1
    none
  end)
  queue.push(Mail { to: "x" }).unwrap()
  -- a worker marked it and died
  db.execute("UPDATE jobs SET reserved_at = ?, attempts = 1", [Json.number(clock[0] as float)]).unwrap()
  assert_eq(queue.work_one().unwrap(), false)
  clock[0] += 301000
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(ran[0], 1)
end

#[qq.Retry(tries: 5, backoff: [5, 30])]
struct Patient
  public n: int
end

#[qq.Unique(seconds: 600)]
struct Once
  public key: string
end

#[qq.Delay(seconds: 120)]
struct Later
  public n: int
end

fun test_a_job_can_ask_for_its_own_tries_and_backoff()
  let clock = [1000000]
  let queue = fresh(clock)
  let runs = [0]
  queue.handle<Patient>(fun(p: Patient) -> string?
    runs[0] += 1
    "no"
  end)
  queue.push(Patient { n: 1 }).unwrap()
  assert_eq(queue.work_one().unwrap(), true)
  -- the first wait is 5 seconds (not the default 10)
  clock[0] += 4000
  assert_eq(queue.work_one().unwrap(), false)
  clock[0] += 1500
  assert_eq(queue.work_one().unwrap(), true)
  -- then 30 seconds, and 30 again for the next ones
  clock[0] += 29000
  assert_eq(queue.work_one().unwrap(), false)
  clock[0] += 1500
  assert_eq(queue.work_one().unwrap(), true)
  clock[0] += 31000
  assert_eq(queue.work_one().unwrap(), true)
  clock[0] += 31000
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(runs[0], 5)
  assert_eq(queue.failed().unwrap()[0].attempts, 5)
end

fun test_a_unique_job_is_not_pushed_twice_until_it_is_done()
  let clock = [1000000]
  let queue = fresh(clock)
  let ran = [0]
  queue.handle<Once>(fun(o: Once) -> string?
    ran[0] += 1
    none
  end)
  assert_eq(queue.push(Once { key: "a" }).unwrap(), true)
  assert_eq(queue.push(Once { key: "a" }).unwrap(), false)
  assert_eq(queue.push(Once { key: "b" }).unwrap(), true)
  assert_eq(queue.pending().unwrap(), 2)
  queue.work(true).unwrap()
  assert_eq(ran[0], 2)
  -- done: the lock is free again
  assert_eq(queue.push(Once { key: "a" }).unwrap(), true)
end

fun test_a_unique_lock_ends_by_itself()
  let clock = [1000000]
  let queue = fresh(clock)
  assert_eq(queue.push(Once { key: "a" }).unwrap(), true)
  clock[0] += 601000
  assert_eq(queue.push(Once { key: "a" }).unwrap(), true)
end

fun test_a_job_can_have_a_delay_of_its_own()
  let clock = [1000000]
  let queue = fresh(clock)
  let ran = [0]
  queue.handle<Later>(fun(l: Later) -> string?
    ran[0] += 1
    none
  end)
  queue.push(Later { n: 1 }).unwrap()
  assert_eq(queue.work_one().unwrap(), false)
  clock[0] += 121000
  assert_eq(queue.work_one().unwrap(), true)
  queue.push_in(Later { n: 2 }, 0).unwrap()
  assert_eq(queue.work_one().unwrap(), true)
end

fun test_middleware_can_skip_wait_and_wrap_a_job()
  let clock = [1000000]
  let queue = fresh(clock)
  let seen: array<string> = []
  queue.use(fun(job: qq.Job, next: qq.JobNext) -> qq.Outcome
    seen.push("before {job.kind}")
    let out = next()
    seen.push("after {out.status}")
    out
  end)
  queue.handle<Mail>(fun(m: Mail) -> string?
    seen.push("run")
    none
  end)
  queue.push(Mail { to: "x" }).unwrap()
  queue.work(true).unwrap()
  assert_eq(seen, ["before Mail", "run", "after done"])
end

fun test_a_released_job_waits_without_using_an_attempt()
  let clock = [1000000]
  let queue = fresh(clock)
  queue.max_attempts = 1
  let busy = [true]
  let ran = [0]
  queue.use(fun(job: qq.Job, next: qq.JobNext) -> qq.Outcome
    if busy[0] then qq.Outcome.release(30) else next() end
  end)
  queue.handle<Mail>(fun(m: Mail) -> string?
    ran[0] += 1
    none
  end)
  queue.push(Mail { to: "x" }).unwrap()
  -- released three times: with one attempt allowed it would be abandoned if releases counted
  assert_eq(queue.work_one().unwrap(), true)
  clock[0] += 31000
  assert_eq(queue.work_one().unwrap(), true)
  clock[0] += 31000
  busy[0] = false
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(ran[0], 1)
  assert_eq(queue.failed().unwrap().len(), 0)
end

fun test_rate_limited_lets_a_number_of_jobs_through_per_window()
  let clock = [1000000]
  let queue = fresh(clock)
  let ran = [0]
  queue.use(qq.rate_limited(cc.Cache.memory(), qq.by_kind, 2, 3600))
  queue.handle<Mail>(fun(m: Mail) -> string?
    ran[0] += 1
    none
  end)
  for i in 0..4 do
    queue.push(Mail { to: "{i}" }).unwrap()
  end
  -- four are ready: two run, two are released for the next window
  for i in 0..4 do
    queue.work_one().unwrap()
  end
  assert_eq(ran[0], 2)
  assert_eq(queue.pending().unwrap(), 2)
  assert_eq(queue.failed().unwrap().len(), 0)
end

fun test_without_overlapping_gives_back_a_job_while_another_runs()
  let clock = [1000000]
  let queue = fresh(clock)
  let cache = cc.Cache.memory()
  let ran = [0]
  queue.use(qq.without_overlapping(cache, qq.by_kind, 60, 5))
  queue.handle<Mail>(fun(m: Mail) -> string?
    ran[0] += 1
    none
  end)
  -- somebody holds the key
  cache.increment("jobs-lock:Mail", 60)
  queue.push(Mail { to: "x" }).unwrap()
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(ran[0], 0)
  cache.forget("jobs-lock:Mail")
  clock[0] += 6000
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(ran[0], 1)
  -- and it frees the key itself
  queue.push(Mail { to: "y" }).unwrap()
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(ran[0], 2)
end

fun test_work_with_stops_after_a_number_of_jobs()
  let clock = [1000000]
  let queue = fresh(clock)
  queue.handle<Mail>(fun(m: Mail) -> string? none end)
  for i in 0..5 do
    queue.push(Mail { to: "{i}" }).unwrap()
  end
  assert_eq(queue.work_with(qq.WorkOptions { max_jobs: 2 }).unwrap(), 2)
  assert_eq(queue.pending().unwrap(), 3)
  assert_eq(queue.work_with(qq.WorkOptions { once: true }).unwrap(), 3)
end

#[qq.OnQueue(name: "high")]
struct Urgent
  public n: int
end

struct Step1
  public n: int
end

struct Step2
  public n: int
end

struct Summary
  public total: int
end

struct Broken
  public n: int
end

struct Alarm
  public why: string
end

--" A queue with a second queue, `high`, in the same database. --"
fun with_high(clock: array<int>) -> qq.Queue
  let db = Db.connect("sqlite://:memory:").unwrap()
  let queue = qq.Queue.new(db, "sqlite")
  queue.lane("high", qq.DbDriver { db: db, dialect: "sqlite", table: "jobs_high" })
  queue.clock = fun() -> int clock[0] end
  queue.install().unwrap()
  queue
end

fun test_a_job_goes_to_the_queue_its_annotation_names_and_high_goes_first()
  let clock = [1000000]
  let queue = with_high(clock)
  let order: array<string> = []
  queue.handle<Resize>(fun(r: Resize) -> string?
    order.push("resize")
    none
  end)
  queue.handle<Urgent>(fun(u: Urgent) -> string?
    order.push("urgent")
    none
  end)
  queue.push(Resize { id: 1 }).unwrap()
  queue.push(Urgent { n: 1 }).unwrap()
  assert_eq(queue.pending().unwrap(), 2)
  -- the order of the queues decides: serve `high` first
  let done = queue.work_with(qq.WorkOptions { once: true, queues: ["high", "default"] }).unwrap()
  assert_eq(done, 2)
  assert_eq(order, ["urgent", "resize"])
end

fun test_a_worker_can_serve_one_queue_only_and_an_unknown_queue_is_an_error()
  let clock = [1000000]
  let queue = with_high(clock)
  let order: array<string> = []
  queue.handle<Resize>(fun(r: Resize) -> string?
    order.push("resize")
    none
  end)
  queue.handle<Urgent>(fun(u: Urgent) -> string?
    order.push("urgent")
    none
  end)
  queue.push(Resize { id: 1 }).unwrap()
  queue.push_on("high", Resize { id: 2 }).unwrap()
  assert_eq(queue.work_with(qq.WorkOptions { once: true, queues: ["default"] }).unwrap(), 1)
  assert_eq(queue.pending().unwrap(), 1)
  assert(queue.work_with(qq.WorkOptions { once: true, queues: ["nope"] }).is_err())
end

fun test_a_chain_runs_its_jobs_in_order_and_stops_at_the_first_that_gives_up()
  let clock = [1000000]
  let queue = with_high(clock)
  let ran: array<string> = []
  queue.handle<Step1>(fun(s: Step1) -> string?
    ran.push("one")
    none
  end)
  queue.handle<Step2>(fun(s: Step2) -> string?
    ran.push("two")
    none
  end)
  queue.chain().add(Step1 { n: 1 }).add(Step2 { n: 2 }).add(Step1 { n: 3 }).dispatch().unwrap()
  assert_eq(queue.pending().unwrap(), 1)
  assert_eq(queue.work(true).unwrap(), 3)
  assert_eq(ran, ["one", "two", "one"])

  -- a failing link: the rest never starts and the alarm is raised
  let alarms: array<string> = []
  queue.max_attempts = 1
  queue.handle<Broken>(fun(b: Broken) -> string?
    "boom"
  end)
  queue.handle<Alarm>(fun(a: Alarm) -> string?
    alarms.push(a.why)
    none
  end)
  queue.chain().add(Step1 { n: 9 }).add(Broken { n: 1 }).add(Step2 { n: 9 }).on_failure(Alarm { why: "chain" }).dispatch().unwrap()
  queue.work(true).unwrap()
  assert_eq(ran, ["one", "two", "one", "one"])
  assert_eq(alarms, ["chain"])
end

fun test_a_batch_pushes_its_follow_up_when_every_job_is_done_and_its_alarm_once()
  let clock = [1000000]
  let queue = with_high(clock)
  let total = [0]
  let follow: array<int> = []
  queue.handle<Resize>(fun(r: Resize) -> string?
    total[0] += r.id
    none
  end)
  queue.handle<Summary>(fun(s: Summary) -> string?
    follow.push(s.total)
    none
  end)
  queue.batch().add(Resize { id: 1 }).add(Resize { id: 2 }).add(Resize { id: 3 }).when_done(Summary { total: 6 }).dispatch().unwrap()
  -- the follow-up only exists once the three are done
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(queue.pending().unwrap(), 1)
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(queue.pending().unwrap(), 1)
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(total[0], 6)
  assert_eq(follow, [6])

  -- two jobs give up: one alarm, and no follow-up
  let alarms: array<string> = []
  queue.max_attempts = 1
  queue.handle<Broken>(fun(b: Broken) -> string?
    "boom"
  end)
  queue.handle<Alarm>(fun(a: Alarm) -> string?
    alarms.push(a.why)
    none
  end)
  queue.batch().add(Broken { n: 1 }).add(Broken { n: 2 }).when_done(Summary { total: 0 }).when_failed(Alarm { why: "batch" }).dispatch().unwrap()
  queue.work(true).unwrap()
  assert_eq(alarms, ["batch"])
  assert_eq(follow, [6])
  assert_eq(queue.failed().unwrap().len(), 2)
end

fun test_an_empty_batch_pushes_the_follow_up_at_once()
  let clock = [1000000]
  let queue = with_high(clock)
  let follow: array<int> = []
  queue.handle<Summary>(fun(s: Summary) -> string?
    follow.push(s.total)
    none
  end)
  queue.batch().when_done(Summary { total: 1 }).dispatch().unwrap()
  queue.work(true).unwrap()
  assert_eq(follow, [1])
end

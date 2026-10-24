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

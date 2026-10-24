-- The queue on Redis. Needs a server: set QLANG_TEST_REDIS to a URL such as redis://127.0.0.1:6379/9
-- (without it each test returns at once).
import "queue.q" as qq

struct Mail
  public to: string
end

--" A queue with its own name in Redis and a clock moved by hand, or `none` when there is no server. --"
fun fresh(clock: array<int>, name: string) -> qq.Queue?
  let url = env.get("QLANG_TEST_REDIS")
  if url == none then
    return none
  end
  let r = Redis.connect(url).unwrap()
  r.command(["FLUSHDB"]).unwrap()
  let queue = qq.Queue.redis(r, name)
  queue.clock = fun() -> int clock[0] end
  queue.install().unwrap()
  queue
end

fun test_a_job_is_done_by_its_handler_and_removed()
  let clock = [1000000]
  let queue = fresh(clock, "t1")
  if queue == none then
    return
  end
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

fun test_jobs_come_in_order_and_a_delayed_job_waits_for_its_time()
  let clock = [1000000]
  let queue = fresh(clock, "t2")
  if queue == none then
    return
  end
  let order: array<string> = []
  queue.handle<Mail>(fun(m: Mail) -> string?
    order.push(m.to)
    none
  end)
  queue.push_in(Mail { to: "later" }, 60).unwrap()
  queue.push(Mail { to: "a" }).unwrap()
  queue.push(Mail { to: "b" }).unwrap()
  assert_eq(queue.work(true).unwrap(), 2)
  assert_eq(order, ["a", "b"])
  assert_eq(queue.pending().unwrap(), 1)
  clock[0] += 61000
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(order, ["a", "b", "later"])
end

fun test_a_failing_job_is_tried_again_then_gives_up_and_can_be_retried()
  let clock = [1000000]
  let queue = fresh(clock, "t3")
  if queue == none then
    return
  end
  let tries = [0]
  queue.handle<Mail>(fun(m: Mail) -> string?
    tries[0] += 1
    "smtp down"
  end)
  queue.push(Mail { to: "x" }).unwrap()
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(queue.work_one().unwrap(), false)
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
  assert_eq(queue.retry_failed(failed[0].id).unwrap(), true)
  assert_eq(queue.failed().unwrap().len(), 0)
  assert_eq(queue.pending().unwrap(), 1)
  assert_eq(queue.forget_failed("nope").unwrap(), false)
end

fun test_a_job_left_running_by_a_dead_worker_is_given_again()
  let clock = [1000000]
  let queue = fresh(clock, "t4")
  if queue == none then
    return
  end
  let ran = [0]
  queue.handle<Mail>(fun(m: Mail) -> string?
    ran[0] += 1
    none
  end)
  queue.push(Mail { to: "x" }).unwrap()
  -- a worker takes it and dies
  assert_eq(queue.driver.claim(clock[0], queue.timeout, 0).unwrap() != none, true)
  assert_eq(queue.work_one().unwrap(), false)
  clock[0] += 301000
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(ran[0], 1)
end

fun test_a_worker_with_nothing_to_do_waits_on_the_queue()
  let clock = [1000000]
  let queue = fresh(clock, "t5")
  if queue == none then
    return
  end
  let started = time.now()
  assert_eq(queue.driver.claim(clock[0], queue.timeout, 1).unwrap() == none, true)
  assert(time.now() - started >= 900)
end

fun test_a_job_without_a_handler_goes_to_the_failed_list()
  let clock = [1000000]
  let queue = fresh(clock, "t6")
  if queue == none then
    return
  end
  queue.push(Mail { to: "x" }).unwrap()
  assert_eq(queue.work_one().unwrap(), true)
  assert(queue.failed().unwrap()[0].error.contains("no handler"))
end

#[qq.Retry(tries: 4, backoff: [5])]
struct Patient
  public n: int
end

#[qq.Unique(seconds: 600)]
struct Once
  public key: string
end

fun test_a_job_asks_for_its_own_tries_and_backoff()
  let clock = [1000000]
  let queue = fresh(clock, "t7")
  if queue == none then
    return
  end
  let runs = [0]
  queue.handle<Patient>(fun(p: Patient) -> string?
    runs[0] += 1
    "no"
  end)
  queue.push(Patient { n: 1 }).unwrap()
  for i in 0..4 do
    assert_eq(queue.work_one().unwrap(), true)
    clock[0] += 5500
  end
  assert_eq(runs[0], 4)
  assert_eq(queue.failed().unwrap()[0].attempts, 4)
end

fun test_a_unique_job_is_pushed_once_until_it_is_done()
  let clock = [1000000]
  let queue = fresh(clock, "t8")
  if queue == none then
    return
  end
  queue.handle<Once>(fun(o: Once) -> string? none end)
  assert_eq(queue.push(Once { key: "a" }).unwrap(), true)
  assert_eq(queue.push(Once { key: "a" }).unwrap(), false)
  queue.work(true).unwrap()
  assert_eq(queue.push(Once { key: "a" }).unwrap(), true)
end

fun test_a_released_job_keeps_its_attempts()
  let clock = [1000000]
  let queue = fresh(clock, "t9")
  if queue == none then
    return
  end
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
  assert_eq(queue.work_one().unwrap(), true)
  clock[0] += 31000
  assert_eq(queue.work_one().unwrap(), true)
  clock[0] += 31000
  busy[0] = false
  assert_eq(queue.work_one().unwrap(), true)
  assert_eq(ran[0], 1)
  assert_eq(queue.failed().unwrap().len(), 0)
end

struct Part
  public n: int
end

struct Whole
  public total: int
end

fun test_a_batch_and_a_chain_work_on_redis_and_a_second_queue_goes_first()
  let clock = [1000000]
  let queue = fresh(clock, "t9")
  if queue == none then
    return
  end
  let r = Redis.connect(env.get("QLANG_TEST_REDIS") ?? "").unwrap()
  queue.lane("high", qq.RedisDriver { redis: r, name: "t9high" })
  let seen: array<string> = []
  queue.handle<Part>(fun(p: Part) -> string?
    seen.push("part{p.n}")
    none
  end)
  queue.handle<Whole>(fun(w: Whole) -> string?
    seen.push("whole{w.total}")
    none
  end)
  queue.batch().add(Part { n: 1 }).add(Part { n: 2 }).when_done(Whole { total: 3 }).dispatch().unwrap()
  assert_eq(queue.work(true).unwrap(), 3)
  assert_eq(seen, ["part1", "part2", "whole3"])
  queue.chain().add(Part { n: 7 }).add(Whole { total: 7 }).dispatch().unwrap()
  assert_eq(queue.work(true).unwrap(), 2)
  assert_eq(seen.len(), 5)
end

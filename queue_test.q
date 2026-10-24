import "queue.q" as qq

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

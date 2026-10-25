import "schedule.q" as sch
import "web/cache.q" as cc

fun at(y: int, mo: int, d: int, h: int, mi: int) -> datetime
  datetime.of(y, mo, d, h, mi, 0)
end

fun test_fields_accept_stars_lists_ranges_and_steps()
  let c = sch.Cron.parse("*/15 9-17 1,15 * *").unwrap()
  assert_eq(c.minutes, [0, 15, 30, 45])
  assert_eq(c.hours.len(), 9)
  assert_eq(c.days, [1, 15])
  assert_eq(sch.Cron.parse("10-50/20 * * * *").unwrap().minutes, [10, 30, 50])
  assert_eq(sch.Cron.parse("5/20 * * * *").unwrap().minutes, [5, 25, 45])
end

fun test_a_wrong_expression_is_an_error_that_says_which_field()
  assert(sch.Cron.parse("* * * *").is_err())
  assert(sch.Cron.parse("60 * * * *").unwrap_err().message.contains("outside"))
  assert(sch.Cron.parse("*/0 * * * *").is_err())
  assert(sch.Cron.parse("a * * * *").is_err())
  assert(sch.Cron.parse("5-2 * * * *").is_err())
end

fun test_a_cron_matches_its_minutes()
  let nightly = sch.Cron.parse("0 3 * * *").unwrap()
  assert(nightly.matches(at(2026, 10, 24, 3, 0)))
  assert(not nightly.matches(at(2026, 10, 24, 3, 1)))
  assert(not nightly.matches(at(2026, 10, 24, 4, 0)))
  -- 2026-10-26 is a Monday
  let monday = sch.Cron.parse("0 8 * * 1").unwrap()
  assert(monday.matches(at(2026, 10, 26, 8, 0)))
  assert(not monday.matches(at(2026, 10, 27, 8, 0)))
  -- Sunday is 0 or 7
  assert(sch.Cron.parse("0 0 * * 7").unwrap().matches(at(2026, 10, 25, 0, 0)))
  assert(sch.Cron.parse("0 0 * * 0").unwrap().matches(at(2026, 10, 25, 0, 0)))
end

fun test_day_of_month_and_weekday_together_mean_either()
  let both = sch.Cron.parse("0 0 13 * 5").unwrap()
  -- Friday 2026-10-30, and the 13th (a Tuesday)
  assert(both.matches(at(2026, 10, 30, 0, 0)))
  assert(both.matches(at(2026, 10, 13, 0, 0)))
  assert(not both.matches(at(2026, 10, 14, 0, 0)))
end

fun test_a_task_runs_once_per_minute_even_when_asked_twice_or_by_two_machines()
  let cache = cc.Cache.memory()
  let clock = [at(2026, 10, 24, 3, 0).ms()]
  let a = sch.Schedule.new(cache)
  let b = sch.Schedule.new(cache)
  a.clock = fun() -> int clock[0] end
  b.clock = fun() -> int clock[0] end
  let runs = [0]
  let job = fun() -> string?
    runs[0] += 1
    none
  end
  a.cron("report", "0 3 * * *", job)
  b.cron("report", "0 3 * * *", job)
  assert_eq(a.run_due(), 1)
  assert_eq(b.run_due(), 0)
  assert_eq(a.run_due(), 0)
  assert_eq(runs[0], 1)
  -- the next day it runs again
  clock[0] += 86400000
  assert_eq(b.run_due(), 1)
  assert_eq(runs[0], 2)
end

fun test_every_minutes_and_a_failing_task()
  let cache = cc.Cache.memory()
  let clock = [at(2026, 10, 24, 10, 0).ms()]
  let plan = sch.Schedule.new(cache)
  plan.clock = fun() -> int clock[0] end
  let runs = [0]
  plan.every_minutes("tick", 5, fun() -> string?
    runs[0] += 1
    none
  end)
  plan.every_minutes("hourly", 60, fun() -> string? "nope" end)
  assert_eq(plan.run_due(), 2)
  clock[0] += 60000
  assert_eq(plan.run_due(), 0)
  clock[0] += 4 * 60000
  assert_eq(plan.run_due(), 1)
  assert_eq(runs[0], 2)
end

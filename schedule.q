--" # Scheduled tasks

Runs functions at given times (every night, every five minutes, on Mondays at 8): the work that `cron`
does, written in the program, tested like the rest, and safe with several machines.

```
let plan = Schedule.new(Cache.redis(redis, "schedule"))
plan.cron("nightly report", "0 3 * * *", fun() -> string? send_report() end)
plan.every_minutes("clean sessions", 15, fun() -> string? sessions.purge(); none end)
plan.cron("monday digest", "0 8 * * 1", fun() -> string? digest() end)

plan.work()          -- a process that never returns: it looks at the clock every second
plan.run_due()       -- or: call it every minute from cron / systemd timer
```

A task is a function that gives `none` when it went well, or a text that says why it did not (it is logged).
A task does not run twice for the same minute, even with **several machines** running the same schedule: the
first to claim the minute in the cache runs it (use `Cache.redis` or a shared store for that; with the
default memory cache, run one scheduler). A task that panics is not caught: keep tasks short and let long
work go to the job queue (`queue.push`).

A cron expression has five fields: minute (0-59), hour (0-23), day of the month (1-31), month (1-12) and day of
the week (0-6, Sunday is 0 or 7). Each field is `*`, a number, a list `1,15`, a range `9-17`, a step `*/5` or
`10-50/10`. When both the day of the month and the day of the week are given, the task runs when **either** matches,
as in cron. Times are UTC.
--"
import "web/cache.q" as cc

--" The values a cron field allows, or an error. --"
fun parse_field(text: string, low: int, high: int) -> Result<array<int>, Error>
  let allowed: array<int> = []
  for part in text.split(",") do
    let gap = 1
    let range = part
    let slash = part.index_of("/")
    if slash != none then
      let n = int.parse(part.substring(slash + 1, part.len()))
      if n == none or n < 1 then
        return field_error<array<int>>("`{part}`: the step must be a number of 1 or more")
      end
      gap = n
      range = part.substring(0, slash)
    end
    let first = low
    let last = high
    if range != "*" then
      let dash = range.index_of("-")
      if dash == none then
        let n = int.parse(range)
        if n == none then
          return field_error<array<int>>("`{part}` is not a number")
        end
        first = n
        last = if slash != none then high else n end
      else
        let a = int.parse(range.substring(0, dash))
        let b = int.parse(range.substring(dash + 1, range.len()))
        if a == none or b == none then
          return field_error<array<int>>("`{part}` is not a range")
        end
        first = a
        last = b
      end
    end
    if first < low or last > high or first > last then
      return field_error<array<int>>("`{part}` is outside {low}-{high}")
    end
    let v = first
    while v <= last do
      if not allowed.contains(v) then
        allowed.push(v)
      end
      v += gap
    end
  end
  Result<array<int>, Error>.Ok(allowed)
end

fun field_error<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
end

--" A parsed cron expression. --"
struct Cron
  public minutes: array<int>
  public hours: array<int>
  public days: array<int>
  public months: array<int>
  public weekdays: array<int>
  public any_day: bool
  public any_weekday: bool
end

impl Cron
  --" Reads `"m h dom mon dow"`. --"
  public fun parse(text: string) -> Result<Cron, Error>
    let fields = text.trim().split(" ").filter(fun(f: string) -> bool f != "" end)
    if fields.len() != 5 then
      return field_error<Cron>("a cron expression has five fields: minute hour day month weekday")
    end
    let minutes = parse_field(fields[0], 0, 59)
    let hours = parse_field(fields[1], 0, 23)
    let days = parse_field(fields[2], 1, 31)
    let months = parse_field(fields[3], 1, 12)
    let weekdays = parse_field(fields[4], 0, 7)
    for r in [minutes, hours, days, months, weekdays] do
      if r.is_err() then
        return Result<Cron, Error>.Err(r.unwrap_err())
      end
    end
    let wd: array<int> = []
    for d in weekdays.unwrap() do
      let day = if d == 7 then 0 else d end
      if not wd.contains(day) then
        wd.push(day)
      end
    end
    Result<Cron, Error>.Ok(Cron { minutes: minutes.unwrap(), hours: hours.unwrap(), days: days.unwrap(), months: months.unwrap(), weekdays: wd, any_day: fields[2] == "*", any_weekday: fields[4] == "*" })
  end

  --" Whether the expression matches this minute. --"
  public fun matches(self, at: datetime) -> bool
    if not self.minutes.contains(at.minute()) or not self.hours.contains(at.hour()) or not self.months.contains(at.month()) then
      return false
    end
    let day_ok = self.days.contains(at.day())
    let weekday = at.weekday() mod 7
    let weekday_ok = self.weekdays.contains(weekday)
    if self.any_day and self.any_weekday then
      return true
    end
    if self.any_day then
      return weekday_ok
    end
    if self.any_weekday then
      return day_ok
    end
    day_ok or weekday_ok
  end
end

--" One task of the schedule. --"
struct Task
  public name: string
  public cron: Cron
  public run: fun() -> string?
end

--" A list of tasks. --"
struct Schedule
  public cache: cc.Cache
  public tasks: array<Task>
  --" The time in milliseconds; tests give their own. --"
  public clock: fun() -> int
end

impl Schedule
  --" `cache` is where machines agree on who runs a minute. --"
  public fun new(cache: cc.Cache) -> Schedule
    Schedule { cache: cache, tasks: [], clock: fun() -> int time.now() end }
  end

  --" A task on a cron expression. Panics if the expression is wrong (it is a mistake in the program, found at start). --"
  public fun cron(self, name: string, expression: string, run: fun() -> string?)
    let parsed = Cron.parse(expression)
    if parsed.is_err() then
      panic("schedule `{name}`: {parsed.unwrap_err().message}")
    end
    self.tasks.push(Task { name: name, cron: parsed.unwrap(), run: run })
  end

  --" A task every `n` minutes (1 to 59), or every `n/60` hours when `n` is a multiple of 60 up to a day. --"
  public fun every_minutes(self, name: string, n: int, run: fun() -> string?)
    if n >= 60 and n mod 60 == 0 and n <= 1440 then
      self.cron(name, "0 */{n div 60} * * *", run)
    else
      self.cron(name, "*/{n} * * * *", run)
    end
  end

  --" A task every day at `hour`:`minute` UTC. --"
  public fun daily_at(self, name: string, hour: int, minute: int, run: fun() -> string?)
    self.cron(name, "{minute} {hour} * * *", run)
  end

  --" Runs the tasks that are due this minute and that nobody ran yet. Gives how many ran. Call it at least once
  a minute (`work` does). --"
  public fun run_due(self) -> int
    let now = self.clock()
    let minute = now div 60000
    let at = datetime.at(minute * 60000)
    let ran = 0
    for task in self.tasks do
      if not task.cron.matches(at) then
        continue
      end
      -- the first machine to count 1 for this minute runs the task
      if self.cache.increment("{task.name}:{minute}", 120) != 1 then
        continue
      end
      let why = task.run()
      if why != none then
        Log.error("scheduled task {task.name} failed: {why}")
      end
      ran += 1
    end
    ran
  end

  --" Looks at the clock every second and runs what is due, until the process is told to stop. --"
  public fun work(self)
    let last = -1
    while not Process.stopping() do
      let minute = self.clock() div 60000
      if minute != last then
        last = minute
        self.run_due()
      end
      time.sleep(1000)
    end
  end
end

export Cron, Task, Schedule

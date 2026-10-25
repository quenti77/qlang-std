-- The scheduler process:  qlang run examples/deploy/scheduler.q
-- One copy per machine is fine: with a shared cache (Redis) each task runs once per minute overall.
import "../../schedule.q" as sch
import "../../web/cache.q" as cc

let redis_url = env.get("REDIS_URL")
let cache = if redis_url == none then cc.Cache.memory() else cc.Cache.redis(Redis.connect(redis_url).unwrap(), "schedule") end
let plan = sch.Schedule.new(cache)
plan.every_minutes("heartbeat", 1, fun() -> string?
  Log.info("scheduler is alive")
  none
end)
plan.work()

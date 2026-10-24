import "events.q" as ev

struct Registered
  public id: int
end

struct Deleted
  public id: int
end

fun test_listeners_get_the_events_of_their_type_in_order()
  let events = ev.Events.new()
  let seen: array<string> = []
  events.listen<Registered>(fun(e: Registered) seen.push("a{e.id}") end)
  events.listen<Registered>(fun(e: Registered) seen.push("b{e.id}") end)
  events.listen<Deleted>(fun(e: Deleted) seen.push("gone{e.id}") end)
  assert_eq(events.dispatch(Registered { id: 1 }), 2)
  assert_eq(events.dispatch(Deleted { id: 7 }), 1)
  assert_eq(seen, ["a1", "b1", "gone7"])
end

fun test_an_event_nobody_listens_to_is_fine()
  let events = ev.Events.new()
  assert_eq(events.dispatch(Registered { id: 1 }), 0)
  assert_eq(events.count<Registered>(), 0)
  events.listen<Registered>(fun(e: Registered) end)
  assert_eq(events.count<Registered>(), 1)
end

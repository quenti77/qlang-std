import "container.q" as web
import "test_services.q" as s

fun good() -> web.Container
  let app = web.Container.new([])
  app
end

fun test_services_are_built_from_the_types_providers_return()
  let app = web.Container.new(Reflect.callables(s))
  let users = app.get<s.Users>().unwrap()
  assert_eq(users.config.host, "smtp.example")
  assert_eq(users.mailer.send("ana"), "smtp.example -> ana")
end

fun test_a_singleton_is_built_once()
  let app = web.Container.new(Reflect.callables(s))
  let a = app.get<s.Config>().unwrap()
  let b = app.get<s.Config>().unwrap()
  assert_eq(a.host, b.host)
  app.get<s.Users>().unwrap()
  assert_eq(s.times_built(), 1)
end

fun test_a_transient_service_is_built_every_time()
  let app = web.Container.new(Reflect.callables(s))
  let a = app.get<s.Counter>().unwrap()
  let b = app.get<s.Counter>().unwrap()
  assert(a.n != b.n)
end

fun test_a_trait_can_be_asked_for_by_its_own_name()
  let app = web.Container.new(Reflect.callables(s))
  let mailer = app.get<s.Mailer>().unwrap()
  assert_eq(mailer.send("bo"), "smtp.example -> bo")
end

fun test_a_ready_value_replaces_a_provider()
  let app = web.Container.new(Reflect.callables(s))
  app.set(s.Config { host: "test.local" })
  assert_eq(app.get<s.Users>().unwrap().config.host, "test.local")
end

fun test_scoped_services_belong_to_one_request()
  let app = web.Container.new(Reflect.callables(s))
  assert(app.get<s.Cart>().is_err())
  let one = app.child()
  one.set(s.Session { id: 1 })
  let two = app.child()
  two.set(s.Session { id: 2 })
  assert_eq(one.get<s.Cart>().unwrap().session.id, 1)
  assert_eq(two.get<s.Cart>().unwrap().session.id, 2)
  assert_eq(one.get<s.Cart>().unwrap().session.id, 1)
  -- singletons are shared by all the requests
  assert_eq(one.get<s.Config>().unwrap().host, two.get<s.Config>().unwrap().host)
  assert_eq(s.times_built(), 1)
end

fun test_a_missing_service_is_an_error_that_names_who_needed_it()
  let app = web.Container.new(Reflect.callables(s))
  let r = app.get<s.Lonely>()
  assert(r.is_err())
  assert_eq(r.unwrap_err().message, "no service of type Session (needed by Lonely)")
  assert(not app.has<s.Session>())
  assert(app.has<s.Config>())
end

fun test_a_service_that_needs_itself_is_caught()
  let app = web.Container.new(Reflect.callables(s))
  let r = app.get<s.Loop1>()
  assert(r.is_err())
  assert(r.unwrap_err().message.contains("Loop1 -> Loop2 -> Loop1"))
end

fun test_validate_reports_every_mistake_before_the_first_request()
  let app = web.Container.new(Reflect.callables(s))
  let problems = app.validate()
  assert(problems.contains("Lonely needs Session: no provider"))
  assert(problems.any(fun(p: string) -> bool p.starts_with("cycle: ") end))
  -- telling the container that requests bring a Session removes the first one
  app.expects<s.Session>()
  assert(not app.validate().contains("Lonely needs Session: no provider"))
end

fun test_a_singleton_may_not_hold_a_request_service()
  let app = web.Container.new(Reflect.callables(s))
  app.expects<s.Session>()
  assert(app.validate().contains("Lonely is a singleton but needs Session, which changes with every request"))
end

import "app.q" as web
import "test_discover.q" as parts
import "test_prefixes.q" as prefixes

fun test_boot_finds_functions_and_controller_structures()
    let app = web.App.boot(Reflect.declared(parts))
    assert_eq(app.handle(Request { method: "GET", url: "/ping", path: "/ping" }).body, "pong")
    let r = app.handle(Request { method: "GET", url: "/greetings/ada", path: "/greetings/ada" })
    assert_eq(r.body, "hello ada at 42")
    let index = app.handle(Request { method: "GET", url: "/greetings", path: "/greetings" })
    assert_eq(index.body, "all greetings")
    let lost = app.handle(Request { method: "GET", url: "/lost", path: "/lost" })
    assert_eq(lost.body, "found")
end

fun test_validate_reports_a_declared_controller_nobody_registered()
    let app = web.App.assemble(Reflect.declared(parts).filter(fun(c: Callable) -> bool c.return_type != "LostController" end))
    app.declare(Reflect.declared(parts))
    let problems = app.validate()
    assert_eq(problems.len(), 1)
    assert(problems[0].contains("LostController"))
    assert(problems[0].contains("never registered"))
end

fun test_a_controller_with_a_missing_service_is_a_wiring_problem()
    let app = web.App.assemble(Reflect.declared(parts).filter(fun(c: Callable) -> bool c.return_type != "Clock" end))
    let problems = app.validate()
    assert(not problems.is_empty())
end

fun test_a_prefix_and_a_route_meet_with_one_slash()
    let app = web.App.boot(Reflect.declared(prefixes))
    let get = fun(path: string) -> Response
        app.handle(Request { method: "GET", url: path, path: path })
    end
    assert_eq(get("/login").body, "empty")
    assert_eq(get("/signin").body, "slash")
    assert_eq(get("/").body, "home")
    assert_eq(get("/x/y").body, "trailing")
    assert_eq(get("//login").status, 404)
end

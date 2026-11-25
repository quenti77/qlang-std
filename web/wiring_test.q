import "app.q" as web
import "test_wiring.q" as parts
import Mailer, Smtp, DomainError from "test_wiring.q"

fun test_a_helper_and_a_plain_structure_are_not_providers()
    let app = web.App.boot_with(Reflect.declared(parts), fun(a: web.App) a.bind<Mailer, Smtp>() end)
    assert(app.container.has_key("Config"))
    assert(not app.container.has_key("string"))
    assert(not app.container.has_key("Pair"))
end

fun test_bind_before_the_controllers_are_built()
    let app = web.App.boot_with(Reflect.declared(parts), fun(a: web.App) a.bind<Mailer, Smtp>() end)
    assert_eq(app.handle(Request { method: "GET", url: "/n", path: "/n" }).body, "sent")
end

fun test_a_port_nobody_bound_is_a_wiring_problem()
    let app = web.App.assemble(Reflect.declared(parts))
    assert(not app.validate().is_empty())
end

fun test_on_error_turns_a_domain_error_into_a_response()
    let app = web.App.boot_with(Reflect.declared(parts), fun(a: web.App)
        a.bind<Mailer, Smtp>()
        a.on_error<DomainError>(fun(e: DomainError) -> web.Problem
            match e
                case NotFound(what) then web.Problem { status: 404, message: "{what} not found" }
                case Forbidden then web.Problem { status: 403, message: "forbidden" }
            end
        end)
    end)
    let found = app.handle(Request { method: "GET", url: "/missing", path: "/missing" })
    assert_eq(found.status, 404)
    assert(found.body.contains("post not found"))
    assert_eq(app.handle(Request { method: "GET", url: "/forbidden", path: "/forbidden" }).status, 403)
end

fun test_an_error_nobody_handles_stays_a_500()
    let app = web.App.boot_with(Reflect.declared(parts), fun(a: web.App) a.bind<Mailer, Smtp>() end)
    assert_eq(app.handle(Request { method: "GET", url: "/missing", path: "/missing" }).status, 500)
end

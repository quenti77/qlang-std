-- Providers, a helper, a plain structure, a port and its adapter.
import Controller, Get from "app.q"
import Service, Helper from "container.q"

struct Config
    public name: string
end

fun make_config() -> Config
    Config { name: "x" }
end

#[Helper]
fun label(n: int) -> string
    "n={n}"
end

struct Pair
    public config: Config
    public count: int
end

trait Mailer
    fun send(self) -> string
end

#[Service]
struct Smtp
end

impl Mailer for Smtp
    public fun send(self) -> string
        "sent"
    end
end

#[Service]
struct Notifier
    public mailer: Mailer
end

#[Controller("/n")]
struct NotifyController
    notifier: Notifier
end

impl NotifyController
    #[Get("/")]
    public fun index(self) -> string
        self.notifier.mailer.send()
    end
end

enum DomainError
    NotFound(what: string)
    Forbidden
end

#[Get("/missing")]
fun missing() -> Result<string, DomainError>
    Result<string, DomainError>.Err(DomainError.NotFound("post"))
end

#[Get("/forbidden")]
fun forbidden() -> Result<string, DomainError>
    Result<string, DomainError>.Err(DomainError.Forbidden)
end

export Mailer, Smtp, DomainError, make_config, label, Pair

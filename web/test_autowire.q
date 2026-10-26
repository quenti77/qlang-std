-- Services built from their fields, for the container tests.
import Service, Scoped from "container.q"

trait Mailer
  fun send(self, to: string) -> string
end

struct Config
  public host: string
end

fun make_config() -> Config
  Config { host: "smtp.example" }
end

#[Service]
struct SmtpMailer
  config: Config
end

impl Mailer for SmtpMailer
  public fun send(self, to: string) -> string
    "{self.config.host} -> {to}"
  end
end

#[Service]
struct Notifier
  mailer: Mailer
  config: Config
end

impl Notifier
  public fun welcome(self, who: string) -> string
    self.mailer.send(who)
  end
end

struct Visitor
  public name: string
end

#[Service]
#[Scoped]
struct Greeter
  visitor: Visitor
end

impl Greeter
  public fun hello(self) -> string
    "hello {self.visitor.name}"
  end
end

-- not marked: left out
struct Plain
  config: Config
end

export Mailer, Config, SmtpMailer, Notifier, Visitor, Greeter, Plain, make_config

-- Providers used by the container tests.
import Scoped, Transient from "container.q"

trait Mailer
  fun send(self, to: string) -> string
end

struct SmtpMailer
  public host: string
end

impl Mailer for SmtpMailer
  public fun send(self, to: string) -> string
    "{self.host} -> {to}"
  end
end

struct Config
  public host: string
end

struct Users
  public config: Config
  public mailer: Mailer
end

struct Session
  public id: int
end

struct Cart
  public session: Session
end

struct Counter
  public n: int
end

struct Loop1
  public x: int
end

struct Loop2
  public y: int
end

struct Lonely
  public z: int
end

let built = 0

fun make_config() -> Config
  built += 1
  Config { host: "smtp.example" }
end

fun make_mailer(config: Config) -> Mailer
  SmtpMailer { host: config.host }
end

fun make_users(config: Config, mailer: Mailer) -> Users
  Users { config, mailer }
end

#[Scoped]
fun make_cart(session: Session) -> Cart
  Cart { session }
end

#[Transient]
fun make_counter() -> Counter
  built += 1
  Counter { n: built }
end

fun make_loop1(b: Loop2) -> Loop1
  Loop1 { x: 1 }
end

fun make_loop2(a: Loop1) -> Loop2
  Loop2 { y: 1 }
end

fun make_lonely(missing: Session) -> Lonely
  Lonely { z: 1 }
end

fun times_built() -> int
  built
end

export Mailer, SmtpMailer, Config, Users, Session, Cart, Counter, Loop1, Loop2, Lonely, times_built

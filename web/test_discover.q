-- Controllers found by `App.discover`/`boot`, for the app tests.
import Controller, Get, Path from "app.q"
import Service from "container.q"

struct Clock
  public now: int
end

fun make_clock() -> Clock
  Clock { now: 42 }
end

#[Service]
struct Greeter
  clock: Clock
end

impl Greeter
  public fun greet(self, name: string) -> string
    "hello {name} at {self.clock.now}"
  end
end

#[Controller("/greetings")]
struct GreetingsController
  greeter: Greeter
end

impl GreetingsController
  #[Get("/:name")]
  public fun show(self, #[Path] name: string) -> string
    self.greeter.greet(name)
  end

  #[Get("/")]
  public fun index(self) -> string
    "all greetings"
  end
end

#[Get("/ping")]
fun ping() -> string
  "pong"
end

-- never registered by hand: only `declare` knows about it
#[Controller("/lost")]
struct LostController
  clock: Clock
end

impl LostController
  #[Get("/")]
  public fun index(self) -> string
    "found"
  end
end

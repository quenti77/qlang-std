-- Commands for the tests of `cli.q`.
import "cli.q" as cli

struct Counter
  public total: int
end

fun make_counter() -> Counter
  Counter { total: 0 }
end

#[cli.Command("greet", "Says hello")]
fun greet(#[cli.Arg(description: "who to greet")] name: string, #[cli.Opt(short: "l", description: "shout")] loud: bool, console: cli.Console) -> int
  let text = "Hello {name}"
  console.line(if loud then text.upper() else text end)
  0
end

#[cli.Command("math:add", "Adds numbers")]
fun add(#[cli.Arg] numbers: array<int>, #[cli.Opt(short: "t")] times: int?, counter: Counter, console: cli.Console)
  let sum = 0
  for n in numbers do
    sum += n
  end
  counter.total += sum
  console.line("{sum * (times ?? 1)}")
end

#[cli.Command("math:total", "The total so far")]
fun total(counter: Counter, console: cli.Console)
  console.line("{counter.total}")
end

#[cli.Command("fail", "Always fails")]
fun fail() -> Result<int, Error>
  Result<int, Error>.Err(Error { message: "it broke" })
end

#[cli.Command("code")]
fun code(#[cli.Opt] value: int) -> int
  value
end

#[cli.Command("ask")]
fun ask(console: cli.Console) -> int
  let name = console.ask("Name?")
  if console.confirm("Sure {name}?", false) then
    console.line("ok {name}")
    return 0
  end
  1
end

#[cli.Command("tags")]
fun tags(#[cli.Opt] tag: array<string>, #[cli.Arg] note: string?, console: cli.Console)
  console.line("{tag.join("+")}|{note ?? "-"}")
end

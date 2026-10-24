--" # Command-line commands

A command is a function. Its parameters say where their values come from; what it returns is its
exit code. The `Cli` finds the commands by their annotation, reads the command line, fills the
parameters and runs the command, as `web/app.q` does for routes.

```
-- commands.q
import "@std/cli.q" as cli

#[cli.Command("greet", "Says hello")]
fun greet(#[cli.Arg] name: string, #[cli.Opt(short: "l")] loud: bool, console: cli.Console) -> int
  let text = "Hello {name}"
  console.line(if loud then text.upper() else text end)
  0
end
```

```
-- main.q
import "@std/cli.q" as cli
import "commands.q" as commands

let app = cli.Cli.new(Reflect.callables(providers))     -- the services the commands need
app.named("tool")
app.add(Reflect.callables(commands))
app.main()
```

```sh
qlang run main.q -- greet Ada --loud      # HELLO ADA
qlang run main.q -- help                  # the list of commands
qlang run main.q -- greet --help          # the usage of one command
```

| Parameter | Filled with |
| --- | --- |
| `#[cli.Arg] name: string` | the next word that is not an option; it must be there unless its type is nullable (`string?`) |
| `#[cli.Arg] files: array<string>` | every word left (the last `Arg` only) |
| `#[cli.Opt] count: int` | `--count 3` or `--count=3`; `--name` is the name of the parameter, or `name:` of the annotation; `short: "c"` allows `-c 3`; absent is an error unless the type is nullable |
| `#[cli.Opt] force: bool` | `--force` (present: `true`; absent: `false`) |
| `#[cli.Opt] tag: array<string>` | `--tag a --tag b` |
| `console: cli.Console` | the console of this run: `line`, `error`, `table`, `ask`, `confirm` |
| any other `name: SomeType` | the service of that type |

The value of an argument or option is read as the type of the parameter (`int`, `float`, `bool`,
`uuid`, `datetime`...); an invalid one is a usage error (exit code `2`).

What the command returns: an `int` is the exit code; a `Result` gives `0` for an `Ok` and shows the
message of an `Err` on the error output with code `1`; no value is `0`.

Command names may be grouped with a colon (`db:migrate`, `db:seed`): the list shows them together.
`Cli.run(args, console)` runs without touching the process, with a `Console.captured()`: that is how
commands are tested.
--"
import "web/container.q" as di

--" `#[Command("db:migrate", "Runs the migrations")]`: this function is a command. --"
#[annotation]
struct Command
  name: string
  description: string = ""
end

--" `#[Arg]`: a positional argument. The name shown in the usage defaults to the parameter's. --"
#[annotation]
struct Arg
  name: string = ""
  description: string = ""
end

--" `#[Opt(name: "count", short: "c", description: "...")]`: an option `--count` (`-c`). --"
#[annotation]
struct Opt
  name: string = ""
  short: string = ""
  description: string = ""
end

--" What a command talks to: standard output and input, or lists in memory for a test. --"
struct Console
  public out: array<string>
  public err: array<string>
  answers: array<string>
  taken: int
  live: bool
end

impl Console
  --" The terminal: `line` prints, `error` writes on the error output, `ask` reads. --"
  public fun stdio() -> Console
    Console { out: [], err: [], answers: [], taken: 0, live: true }
  end

  --" A console that keeps what is written; `answers` are what `ask` and `confirm` receive. --"
  public fun captured(answers: array<string>) -> Console
    Console { out: [], err: [], answers: answers, taken: 0, live: false }
  end

  public fun line(self, text: string)
    if self.live then
      print(text)
    else
      self.out.push(text)
    end
  end

  public fun error(self, text: string)
    if self.live then
      eprint(text)
    else
      self.err.push(text)
    end
  end

  --" Everything `line` wrote (captured console), one line each. --"
  public fun output(self) -> string
    self.out.join("\n")
  end

  --" Everything `error` wrote (captured console). --"
  public fun errors(self) -> string
    self.err.join("\n")
  end

  --" Shows the question and gives the line the user types. --"
  public fun ask(self, question: string) -> string
    if self.live then
      write("{question} ")
      return read()
    end
    self.out.push(question)
    if self.taken >= self.answers.len() then
      return ""
    end
    let a = self.answers[self.taken]
    self.taken += 1
    a
  end

  --" Asks a yes/no question; an empty answer is `fallback`. --"
  public fun confirm(self, question: string, fallback: bool) -> bool
    let hint = if fallback then "[Y/n]" else "[y/N]" end
    let a = self.ask("{question} {hint}").trim().lower()
    if a == "" then
      return fallback
    end
    a == "y" or a == "yes" or a == "o" or a == "oui"
  end

  --" A table: the headers, a line of dashes, then the rows, each column as wide as its widest cell. --"
  public fun table(self, headers: array<string>, rows: array<array<string>>)
    let widths: array<int> = []
    for h in headers do
      widths.push(h.len())
    end
    for row in rows do
      for i in 0..row.len() do
        if i < widths.len() and row[i].len() > widths[i] then
          widths[i] = row[i].len()
        end
      end
    end
    self.line(cells(headers, widths))
    self.line(widths.map(fun(w: int) -> string "-".repeat(w) end).join("  "))
    for row in rows do
      self.line(cells(row, widths))
    end
  end
end

fun cells(row: array<string>, widths: array<int>) -> string
  let parts: array<string> = []
  for i in 0..widths.len() do
    let text = if i < row.len() then row[i] else "" end
    parts.push(text.pad_right(widths[i], " "))
  end
  parts.join("  ").trim()
end

--" One parameter of a command, as the command line sees it. --"
struct Param
  public info: ParamInfo
  --" `arg`, `opt` or `service`. --"
  public kind: string
  public name: string
  public short: string
  public description: string
  public flag: bool
  public many: bool
  public optional: bool
end

--" A command found by its annotation. --"
struct CommandDef
  public name: string
  public description: string
  public params: array<Param>
  public run: Callable
end

--" The set of commands of a program. --"
struct Cli
  public container: di.Container
  public program: string
  commands: array<CommandDef>
  problems: array<string>
end

fun str_of(a: AnnotationInfo, field: string) -> string
  a.get_string(field) ?? ""
end

fun param_of(p: ParamInfo) -> Param
  let kind = "service"
  let name = p.name
  let short = ""
  let description = ""
  let arg = p.annotation("Arg")
  let opt = p.annotation("Opt")
  if arg != none then
    kind = "arg"
    if str_of(arg, "name") != "" then
      name = str_of(arg, "name")
    end
    description = str_of(arg, "description")
  end
  if opt != none then
    kind = "opt"
    if str_of(opt, "name") != "" then
      name = str_of(opt, "name")
    end
    short = str_of(opt, "short")
    description = str_of(opt, "description")
  end
  let shape = p.type_info()
  Param { info: p, kind: kind, name: name, short: short, description: description, flag: kind == "opt" and shape.kind == "bool", many: shape.kind == "array", optional: shape.nullable }
end

--" The edit distance between two words (to suggest a command for a typing mistake). --"
fun distance(a: string, b: string) -> int
  let x = a.chars()
  let y = b.chars()
  let prev: array<int> = []
  for j in 0..y.len() + 1 do
    prev.push(j)
  end
  for i in 1..x.len() + 1 do
    let row: array<int> = [i]
    for j in 1..y.len() + 1 do
      let cost = if x[i - 1] == y[j - 1] then 0 else 1 end
      let best = prev[j] + 1
      if row[j - 1] + 1 < best then
        best = row[j - 1] + 1
      end
      if prev[j - 1] + cost < best then
        best = prev[j - 1] + cost
      end
      row.push(best)
    end
    prev = row
  end
  prev[y.len()]
end

impl Cli
  --" A program whose services come from these provider functions (may be empty). --"
  public fun new(providers: array<Callable>) -> Cli
    let c = di.Container.new(providers.filter(fun(p: Callable) -> bool p.annotation("Command") == none end))
    c.expects<Console>()
    Cli { container: c, program: "app", commands: [], problems: [] }
  end

  --" The name of the program in the usage lines. --"
  public fun named(self, program: string)
    self.program = program
  end

  --" Adds the functions that carry `#[Command]`. --"
  public fun add(self, found: array<Callable>)
    for c in found do
      let tag = c.annotation("Command")
      if tag == none then
        continue
      end
      let name = str_of(tag, "name")
      if name == "" then
        self.problems.push("{c.name}: the command has no name")
        continue
      end
      let params: array<Param> = []
      for p in c.params do
        params.push(param_of(p))
      end
      self.commands.push(CommandDef { name: name, description: str_of(tag, "description"), params: params, run: c })
    end
  end

  --" What is wrong with the commands: duplicate names, an `Arg` after an array `Arg`, a service
  that no provider gives. Empty when all is well. --"
  public fun validate(self) -> array<string>
    let out: array<string> = []
    for p in self.problems do
      out.push(p)
    end
    let seen: array<string> = []
    for c in self.commands do
      if seen.contains(c.name) then
        out.push("{c.name}: two commands have this name")
      end
      seen.push(c.name)
      let args = c.params.filter(fun(p: Param) -> bool p.kind == "arg" end)
      for i in 0..args.len() do
        if args[i].many and i < args.len() - 1 then
          out.push("{c.name}: the array argument {args[i].name} must be the last one")
        end
      end
      for p in c.params do
        if p.kind == "service" and not self.container.has_key(p.info.type_name) and p.info.type_name != "Console" then
          out.push("{c.name}: no service of type {p.info.type_name} for {p.name}")
        end
      end
    end
    out
  end

  fun find(self, name: string) -> CommandDef?
    for c in self.commands do
      if c.name == name then
        return c
      end
    end
    none
  end

  --" The list of commands, grouped by the part before the colon. --"
  public fun list(self, console: Console)
    console.line("Usage: {self.program} <command> [options]")
    console.line("")
    console.line("Commands:")
    let names = self.commands.map(fun(c: CommandDef) -> string c.name end)
    let width = 0
    for n in names do
      if n.len() > width then
        width = n.len()
      end
    end
    let sorted = self.commands.filter(fun(c: CommandDef) -> bool true end)
    sorted.sort_by(fun(a: CommandDef, b: CommandDef) -> int
      if a.name < b.name then -1 else (if a.name > b.name then 1 else 0 end) end
    end)
    let group = ""
    for c in sorted do
      let at = c.name.index_of(":")
      let this = if at == none then "" else c.name.substring(0, at) end
      if this != group and this != "" then
        console.line(" {this}")
      end
      group = this
      console.line("  {c.name.pad_right(width, " ")}  {c.description}".trim_end())
    end
    console.line("")
    console.line("Run `{self.program} <command> --help` for the usage of one command.")
  end

  --" The usage of one command: its form, then its arguments and options. --"
  public fun usage(self, c: CommandDef, console: Console)
    let form = "{self.program} {c.name}"
    let has_opts = false
    for p in c.params do
      if p.kind == "opt" then
        has_opts = true
      end
    end
    if has_opts then
      form = form + " [options]"
    end
    for p in c.params do
      if p.kind == "arg" then
        let shown = if p.many then "{p.name}..." else p.name end
        form = form + (if p.optional or p.many then " [{shown}]" else " <{shown}>" end)
      end
    end
    console.line("Usage: {form}")
    if c.description != "" then
      console.line("")
      console.line(c.description)
    end
    let shown_args = c.params.filter(fun(p: Param) -> bool p.kind == "arg" end)
    if shown_args.len() > 0 then
      console.line("")
      console.line("Arguments:")
      for p in shown_args do
        console.line("  {p.name.pad_right(18, " ")}{p.description}".trim_end())
      end
    end
    let shown_opts = c.params.filter(fun(p: Param) -> bool p.kind == "opt" end)
    if shown_opts.len() > 0 then
      console.line("")
      console.line("Options:")
      for p in shown_opts do
        let left = if p.short != "" then "-{p.short}, --{p.name}" else "    --{p.name}" end
        if not p.flag then
          left = left + " <value>"
        end
        console.line("  {left.pad_right(24, " ")}{p.description}".trim_end())
      end
    end
  end

  --" Runs the program with its arguments (`env.args()`) on the terminal and ends the process
  with the exit code. --"
  public fun main(self)
    let problems = self.validate()
    if problems.len() > 0 then
      for p in problems do
        eprint("error: {p}")
      end
      exit(70)
    end
    exit(self.run(env.args(), Console.stdio()))
  end

  --" Runs one command line and gives its exit code: `0` all went well, `1` the command failed,
  `2` the command line is wrong, `127` no such command. Nothing is written but on `console`. --"
  public fun run(self, args: array<string>, console: Console) -> int
    if args.len() == 0 or args[0] == "help" or args[0] == "--help" or args[0] == "-h" then
      if args.len() > 1 and args[0] == "help" then
        let target = self.find(args[1])
        if target != none then
          self.usage(target, console)
          return 0
        end
      end
      self.list(console)
      return 0
    end
    let c = self.find(args[0])
    if c == none then
      console.error("Unknown command {args[0]}")
      let near = self.commands.filter(fun(k: CommandDef) -> bool distance(k.name, args[0]) <= 2 or k.name.starts_with(args[0]) end)
      if near.len() > 0 then
        console.error("Did you mean: {near.map(fun(k: CommandDef) -> string k.name end).join(", ")}?")
      end
      return 127
    end
    let rest = args.slice(1, args.len())
    if rest.contains("--help") or rest.contains("-h") then
      self.usage(c, console)
      return 0
    end
    let values = self.read_line(c, rest)
    if values.is_err() then
      console.error(values.unwrap_err())
      console.error("Run `{self.program} {c.name} --help` for the usage.")
      return 2
    end
    self.execute(c, values.unwrap(), console)
  end

  fun execute(self, c: CommandDef, values: map<string, Any>, console: Console) -> int
    let scope = self.container.child()
    scope.set(console)
    let call: array<Any> = []
    for p in c.params do
      if p.kind == "service" then
        let made = scope.resolve(p.info.type_name, [])
        if made.is_err() then
          console.error("{c.name}: {made.unwrap_err().message}")
          return 70
        end
        call.push(made.unwrap())
      else
        call.push(values[p.name] ?? Any.of(0))
      end
    end
    let out = c.run.call(call)
    if out.is_err() then
      console.error("{c.name}: {out.unwrap_err().message}")
      return 70
    end
    exit_code(out.unwrap(), console)
  end

  --" Reads the words after the command name into a value for each argument and option. --"
  fun read_line(self, c: CommandDef, words: array<string>) -> Result<map<string, Any>, string>
    let raw: map<string, array<string>> = {}
    let positional: array<string> = []
    let opts = c.params.filter(fun(p: Param) -> bool p.kind == "opt" end)
    let i = 0
    let only_words = false
    while i < words.len() do
      let w = words[i]
      i += 1
      if only_words or not w.starts_with("-") or w == "-" then
        positional.push(w)
        continue
      end
      if w == "--" then
        only_words = true
        continue
      end
      let name = ""
      let given: string? = none
      let found: Param? = none
      if w.starts_with("--") then
        name = w.substring(2, w.len())
        let eq = name.index_of("=")
        if eq != none then
          given = name.substring(eq + 1, name.len())
          name = name.substring(0, eq)
        end
        for o in opts do
          if o.name == name then
            found = o
          end
        end
      else
        name = w.substring(1, w.len())
        for o in opts do
          if o.short != "" and o.short == name then
            found = o
          end
        end
      end
      if found == none then
        return Result<map<string, Any>, string>.Err("Unknown option {w}")
      end
      let o = found
      if o.flag then
        if given != none and given != "true" and given != "false" then
          return Result<map<string, Any>, string>.Err("Option --{o.name} takes no value")
        end
        push_raw(raw, o.name, given ?? "true")
      else
        if given == none then
          if i >= words.len() then
            return Result<map<string, Any>, string>.Err("Option --{o.name} needs a value")
          end
          given = words[i]
          i += 1
        end
        push_raw(raw, o.name, given ?? "")
      end
    end
    let out: map<string, Any> = {}
    let next = 0
    for p in c.params do
      if p.kind == "service" then
        continue
      end
      let texts: array<string> = []
      if p.kind == "opt" then
        texts = raw[p.name] ?? []
      else
        if p.many then
          while next < positional.len() do
            texts.push(positional[next])
            next += 1
          end
        else
          if next < positional.len() then
            texts.push(positional[next])
            next += 1
          end
        end
      end
      let made = convert(p, texts)
      if made.is_err() then
        return Result<map<string, Any>, string>.Err(made.unwrap_err())
      end
      out[p.name] = made.unwrap()
    end
    if next < positional.len() then
      return Result<map<string, Any>, string>.Err("Too many arguments: {positional.slice(next, positional.len()).join(" ")}")
    end
    Result<map<string, Any>, string>.Ok(out)
  end
end

fun push_raw(raw: map<string, array<string>>, name: string, text: string)
  let seen = raw[name]
  if seen == none then
    raw[name] = [text]
  else
    seen.push(text)
  end
end

--" The value of a parameter from the words given for it. --"
fun convert(p: Param, texts: array<string>) -> Result<Any, string>
  let shape = p.info.type_info()
  if p.many then
    let item = shape.item
    let kind = if item == none then "string" else item.kind end
    let list: array<Json> = []
    for t in texts do
      if kind == "int" or kind == "float" then
        let n = float.parse(t)
        if n == none then
          return Result<Any, string>.Err("{p.name}: {t} is not a number")
        end
        list.push(Json.number(n))
      else
        if kind == "bool" then
          list.push(Json.boolean(t == "true"))
        else
          list.push(Json.string(t))
        end
      end
    end
    let read = p.info.decode(Json.array(list))
    if read.is_err() then
      return Result<Any, string>.Err("{p.name}: {read.unwrap_err().message}")
    end
    return Result<Any, string>.Ok(read.unwrap())
  end
  if texts.len() == 0 then
    if p.flag then
      return Result<Any, string>.Ok(Any.of(false))
    end
    if shape.nullable then
      return Result<Any, string>.Ok(p.info.parse("").unwrap())
    end
    let what = if p.kind == "opt" then "option --{p.name}" else "argument <{p.name}>" end
    return Result<Any, string>.Err("Missing {what}")
  end
  if texts.len() > 1 then
    return Result<Any, string>.Err("{p.name} was given {texts.len()} times")
  end
  let read = p.info.parse(texts[0])
  if read.is_err() then
    return Result<Any, string>.Err("{p.name}: {read.unwrap_err().message}")
  end
  Result<Any, string>.Ok(read.unwrap())
end

--" The exit code for what a command returned. --"
fun exit_code(a: Any, console: Console) -> int
  let n = a.as<int>()
  if n != none then
    return n
  end
  let parts = Reflect.parts(a)
  if parts != none and parts.enum_name == "Result" then
    if parts.variant == "Ok" then
      return exit_code(parts.values[0], console)
    end
    let e = parts.values[0]
    let plain = e.as<Error>()
    if plain != none then
      console.error(plain.message)
    else
      console.error("failed: {e.type_name()}")
    end
    return 1
  end
  0
end

export Command, Arg, Opt, Console, Cli, CommandDef, Param

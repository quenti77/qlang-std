import "cli.q" as cli
import "test_commands.q" as commands

fun build() -> cli.Cli
  let app = cli.Cli.new(Reflect.callables(commands))
  app.named("tool")
  app.add(Reflect.callables(commands))
  app
end

fun run(app: cli.Cli, args: array<string>) -> (int, string, string)
  let console = cli.Console.captured([])
  let code = app.run(args, console)
  (code, console.output(), console.errors())
end

fun test_the_wiring_is_checked()
  assert_eq(build().validate(), [])
end

fun test_arguments_and_flags_fill_the_parameters()
  let r = run(build(), ["greet", "Ada"])
  assert_eq(r.0, 0)
  assert_eq(r.1, "Hello Ada")
  assert_eq(run(build(), ["greet", "Ada", "--loud"]).1, "HELLO ADA")
  assert_eq(run(build(), ["greet", "-l", "Ada"]).1, "HELLO ADA")
end

fun test_options_take_values_and_arrays_collect_the_rest()
  let app = build()
  assert_eq(run(app, ["math:add", "1", "2", "3"]).1, "6")
  assert_eq(run(app, ["math:add", "1", "2", "--times", "3"]).1, "9")
  assert_eq(run(app, ["math:add", "4", "--times=2"]).1, "8")
  assert_eq(run(app, ["math:add", "-t", "2", "5"]).1, "10")
end

fun test_services_come_from_the_container()
  let app = cli.Cli.new(Reflect.callables(commands))
  app.add(Reflect.callables(commands))
  run(app, ["math:add", "5"])
  assert_eq(run(app, ["math:total"]).1, "5")
end

fun test_an_err_is_exit_1_and_an_int_is_the_exit_code()
  let failed = run(build(), ["fail"])
  assert_eq(failed.0, 1)
  assert(failed.2.contains("it broke"))
  assert_eq(run(build(), ["code", "--value", "7"]).0, 7)
end

fun test_a_wrong_command_line_is_exit_2_with_a_message()
  let app = build()
  let missing = run(app, ["greet"])
  assert_eq(missing.0, 2)
  assert(missing.2.contains("Missing argument <name>"))
  let unknown = run(app, ["greet", "Ada", "--nope"])
  assert_eq(unknown.0, 2)
  assert(unknown.2.contains("Unknown option --nope"))
  let bad = run(app, ["code", "--value", "abc"])
  assert_eq(bad.0, 2)
  assert(bad.2.contains("value"))
  assert_eq(run(app, ["greet", "a", "b"]).0, 2)
  assert_eq(run(app, ["code"]).0, 2)
end

fun test_an_unknown_command_suggests_a_close_one()
  let r = run(build(), ["gret"])
  assert_eq(r.0, 127)
  assert(r.2.contains("Did you mean: greet"))
end

fun test_help_lists_commands_and_describes_one()
  let all = run(build(), [])
  assert_eq(all.0, 0)
  assert(all.1.contains("greet"))
  assert(all.1.contains("Adds numbers"))
  assert(all.1.contains(" math"))
  let one = run(build(), ["greet", "--help"])
  assert(one.1.contains("Usage: tool greet [options] <name>"))
  assert(one.1.contains("-l, --loud"))
  assert(one.1.contains("who to greet"))
  assert_eq(run(build(), ["help", "greet"]).1, one.1)
end

fun test_ask_and_confirm_use_the_answers()
  let app = build()
  let console = cli.Console.captured(["Ada", "y"])
  assert_eq(app.run(["ask"], console), 0)
  assert(console.output().contains("ok Ada"))
  let no = cli.Console.captured(["Ada", ""])
  assert_eq(app.run(["ask"], no), 1)
end

fun test_repeated_options_and_optional_arguments()
  let app = build()
  assert_eq(run(app, ["tags", "--tag", "a", "--tag", "b", "note"]).1, "a+b|note")
  assert_eq(run(app, ["tags"]).1, "|-")
  assert_eq(run(app, ["tags", "--", "--odd"]).1, "|--odd")
end

fun test_a_table_pads_its_columns()
  let console = cli.Console.captured([])
  console.table(["id", "name"], [["1", "Ada"], ["22", "Grace"]])
  assert_eq(console.output(), "id  name\n--  -----\n1   Ada\n22  Grace")
end

fun test_commands_without_a_description_keep_their_indent()
  let all = run(build(), [])
  assert(all.1.contains("\n  ask\n"))
end

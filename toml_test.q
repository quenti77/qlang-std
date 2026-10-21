import "toml.q" as toml

-- the lines of a document, joined (a qlang string cannot span lines)
fun doc(lines: array<string>) -> Json
  assert_ok(toml.parse(lines.join("\n") + "\n"))
end

fun num(j: Json?) -> float
  assert_some(j).as_number()
end

fun str(j: Json?) -> string
  assert_some(j).as_string()
end

fun test_keys_and_scalars()
  let d = doc(["title = \"qlang\"", "port = 8080", "ratio = 0.5", "debug = true", "name = 'literal \\n'"])
  assert_eq(str(d.get("title")), "qlang")
  assert_eq(num(d.get("port")), 8080.0)
  assert_eq(num(d.get("ratio")), 0.5)
  assert_eq(assert_some(d.get("debug")).as_bool(), true)
  assert_eq(str(d.get("name")), "literal \\n")
end

fun test_numbers()
  let d = doc(["a = 1_000", "b = -17", "c = +3", "d = 0xff", "e = 0o17", "f = 0b101", "g = 1e3", "h = -2.5e-1", "i = inf", "j = -inf"])
  assert_eq(num(d.get("a")), 1000.0)
  assert_eq(num(d.get("b")), -17.0)
  assert_eq(num(d.get("c")), 3.0)
  assert_eq(num(d.get("d")), 255.0)
  assert_eq(num(d.get("e")), 15.0)
  assert_eq(num(d.get("f")), 5.0)
  assert_eq(num(d.get("g")), 1000.0)
  assert_close(num(d.get("h")), -0.25)
  assert_eq(num(d.get("i")), float.INFINITY)
  assert_eq(num(d.get("j")), -float.INFINITY)
end

fun test_string_escapes()
  let d = doc(["a = \"tab\\there\"", "b = \"quote \\\" and back\\\\slash\"", "c = \"caf\\u00e9\"", "d = \"line\\nbreak\""])
  assert_eq(str(d.get("a")), "tab\there")
  assert_eq(str(d.get("b")), "quote \" and back\\slash")
  assert_eq(str(d.get("c")), "café")
  assert_eq(str(d.get("d")), "line\nbreak")
end

fun test_multi_line_strings()
  let d = doc(["a = \"\"\"", "one", "two\"\"\"", "b = '''", "raw \\n", "text'''", "c = \"\"\"cut \\", "    here\"\"\""])
  assert_eq(str(d.get("a")), "one\ntwo")
  assert_eq(str(d.get("b")), "raw \\n\ntext")
  assert_eq(str(d.get("c")), "cut here")
end

fun test_comments_and_blank_lines()
  let d = doc(["# a comment", "", "a = 1 # trailing", "   ", "b = \"# not a comment\""])
  assert_eq(num(d.get("a")), 1.0)
  assert_eq(str(d.get("b")), "# not a comment")
end

fun test_tables_and_dotted_keys()
  let d = doc(["[server]", "port = 80", "tls.enabled = true", "", "[server.limits]", "max = 10", "", "[\"quoted name\"]", "x = 1"])
  let server = assert_some(d.get("server"))
  assert_eq(num(server.get("port")), 80.0)
  assert_eq(assert_some(assert_some(server.get("tls")).get("enabled")).as_bool(), true)
  assert_eq(num(assert_some(server.get("limits")).get("max")), 10.0)
  assert_eq(num(assert_some(d.get("quoted name")).get("x")), 1.0)
end

fun test_arrays()
  let d = doc(["a = [1, 2, 3]", "b = [\"x\", \"y\",]", "c = [", "  1, # one", "  2,", "]", "d = [[1, 2], [3]]", "e = []"])
  assert_eq(assert_some(d.get("a")).as_array().len(), 3)
  assert_eq(assert_some(assert_some(d.get("b")).at(1)).as_string(), "y")
  assert_eq(assert_some(d.get("c")).as_array().len(), 2)
  assert_eq(assert_some(assert_some(d.get("d")).at(0)).as_array().len(), 2)
  assert_eq(assert_some(d.get("e")).as_array().len(), 0)
end

fun test_inline_tables()
  let d = doc(["point = \{ x = 1, y = 2 }", "empty = \{}", "nested = \{ a = \{ b = \"c\" } }"])
  let p = assert_some(d.get("point"))
  assert_eq(num(p.get("x")), 1.0)
  assert_eq(num(p.get("y")), 2.0)
  assert_eq(assert_some(d.get("empty")).as_object().len(), 0)
  assert_eq(str(assert_some(assert_some(d.get("nested")).get("a")).get("b")), "c")
end

fun test_arrays_of_tables()
  let d = doc(["[[product]]", "name = \"hammer\"", "", "[[product]]", "name = \"nail\"", "", "[product.dims]", "w = 3"])
  let products = assert_some(d.get("product")).as_array()
  assert_eq(products.len(), 2)
  assert_eq(str(products[0].get("name")), "hammer")
  assert_eq(str(products[1].get("name")), "nail")
  assert_eq(num(assert_some(products[1].get("dims")).get("w")), 3.0)
  assert_none(products[0].get("dims"))
end

fun test_dates_stay_text()
  let d = doc(["day = 1979-05-27", "moment = 1979-05-27T07:32:00Z", "spaced = 1979-05-27 07:32:00", "time = 07:32:00"])
  assert_eq(str(d.get("day")), "1979-05-27")
  assert_eq(str(d.get("moment")), "1979-05-27T07:32:00Z")
  assert_eq(str(d.get("spaced")), "1979-05-27 07:32:00")
  assert_eq(str(d.get("time")), "07:32:00")
end

fun test_a_whole_file_without_a_final_newline()
  let d = assert_ok(toml.parse("[a]\nb = 1"))
  assert_eq(num(assert_some(d.get("a")).get("b")), 1.0)
  assert_eq(assert_ok(toml.parse("")).as_object().len(), 0)
end

fun test_errors_give_the_line()
  assert_contains_text(assert_err(toml.parse("a = 1\nb = \n")).message, "line 2")
  assert_contains_text(assert_err(toml.parse("a = 1\na = 2\n")).message, "defined twice")
  assert_contains_text(assert_err(toml.parse("a 1\n")).message, "`=` was expected")
  assert_contains_text(assert_err(toml.parse("a = \"open\n")).message, "new line")
  assert_contains_text(assert_err(toml.parse("a = [1, 2\n")).message, "never closed")
  assert_contains_text(assert_err(toml.parse("a = nope\n")).message, "not a value")
  assert_contains_text(assert_err(toml.parse("a = 1 2\n")).message, "after the value")
  assert_contains_text(assert_err(toml.parse("[a\nb = 1\n")).message, "`]` was expected")
  assert_contains_text(assert_err(toml.parse("a = 1\n[a]\n")).message, "not a table")
  assert_contains_text(assert_err(toml.parse("a = \"\\q\"\n")).message, "unknown escape")
end

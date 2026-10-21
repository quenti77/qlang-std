import "csv.q" as csv

fun test_simple_rows()
  let rows = assert_ok(csv.parse("a,b,c\n1,2,3\n"))
  assert_eq(rows.len(), 2)
  assert_eq(rows[0], ["a", "b", "c"])
  assert_eq(rows[1], ["1", "2", "3"])
end

fun test_no_final_newline_and_crlf()
  assert_eq(assert_ok(csv.parse("a,b\r\nc,d")), [["a", "b"], ["c", "d"]])
  assert_eq(assert_ok(csv.parse("a,b\r\nc,d\r\n")), [["a", "b"], ["c", "d"]])
end

fun test_quotes_hold_separators_quotes_and_newlines()
  let rows = assert_ok(csv.parse("\"bob, jr\",\"say \"\"hi\"\"\",\"two\nlines\"\n"))
  assert_eq(rows, [["bob, jr", "say \"hi\"", "two\nlines"]])
end

fun test_empty_fields_and_lines()
  assert_eq(assert_ok(csv.parse("a,,c\n")), [["a", "", "c"]])
  assert_eq(assert_ok(csv.parse(",\n")), [["", ""]])
  assert_eq(assert_ok(csv.parse("a\n\nb\n")), [["a"], [""], ["b"]])
  assert_eq(assert_ok(csv.parse("")), [])
  assert_eq(assert_ok(csv.parse("\"\"\n")), [[""]])
end

fun test_another_separator()
  assert_eq(assert_ok(csv.parse_with("a;b\n1;2\n", ";")), [["a", "b"], ["1", "2"]])
  assert_eq(assert_ok(csv.parse_with("a\tb\n", "\t")), [["a", "b"]])
  assert_err(csv.parse_with("a,b", ",,"))
  assert_err(csv.parse_with("a,b", "\""))
end

fun test_an_unclosed_quote_is_an_error()
  let e = assert_err(csv.parse("a,b\n\"oops,c\n"))
  assert_contains_text(e.message, "line 2")
end

fun test_a_quote_in_the_middle_of_a_field_is_kept()
  assert_eq(assert_ok(csv.parse("5\" pipe,x\n")), [["5\" pipe", "x"]])
end

fun test_unicode()
  assert_eq(assert_ok(csv.parse("café,日本語\n")), [["café", "日本語"]])
end

fun test_records_use_the_header()
  let records = assert_ok(csv.parse_records("name,age\nana,31\nbob\n"))
  assert_eq(records.len(), 2)
  assert_eq(records[0]["name"], "ana")
  assert_eq(records[0]["age"], "31")
  assert_eq(records[1]["age"], "")
  assert_eq(assert_ok(csv.parse_records("")).len(), 0)
end

fun test_writing_quotes_only_when_needed()
  let text = csv.to_text([["a", "b,c"], ["say \"hi\"", "x\ny"], ["", "z"]])
  assert_eq(text, "a,\"b,c\"\n\"say \"\"hi\"\"\",\"x\ny\"\n,z\n")
  assert_eq(csv.to_text([]), "")
  assert_eq(csv.to_text_with([["a;b", "c"]], ";"), "\"a;b\";c\n")
end

fun test_writing_then_reading_gives_the_rows_back()
  let rows = [["id", "note"], ["1", "plain"], ["2", "with, comma"], ["3", "quote \" and\nnewline"], ["4", ""]]
  assert_eq(assert_ok(csv.parse(csv.to_text(rows))), rows)
end

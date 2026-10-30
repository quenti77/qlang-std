import "yaml.q" as yaml

-- the lines of a document, joined (a qlang string cannot span lines)
fun doc(lines: array<string>) -> Json
  assert_ok(yaml.parse(lines.join("\n") + "\n"))
end

fun at(j: Json, key: string) -> Json
  assert_some(j.get(key))
end

fun test_scalars_follow_the_core_schema()
  let d = doc(["a: 1", "b: 2.5", "c: true", "d: ~", "e:", "f: hello world", "g: 'it''s'", "h: \"tab\\there\"", "i: yes", "j: 0x1F", "k: -3", "l: 1e3"])
  assert_eq(at(d, "a").as_number(), 1.0)
  assert_eq(at(d, "b").as_number(), 2.5)
  assert_eq(at(d, "c").as_bool(), true)
  assert(at(d, "d").is_null())
  assert(at(d, "e").is_null())
  assert_eq(at(d, "f").as_string(), "hello world")
  assert_eq(at(d, "g").as_string(), "it's")
  assert_eq(at(d, "h").as_string(), "tab\there")
  assert_eq(at(d, "i").as_string(), "yes")
  assert_eq(at(d, "j").as_number(), 31.0)
  assert_eq(at(d, "k").as_number(), -3.0)
  assert_eq(at(d, "l").as_number(), 1000.0)
end

fun test_nested_mappings_and_sequences()
  let d = doc(["server:", "  port: 8080", "  hosts:", "    - a.example", "    - b.example", "tags:", "- x", "- y", "empty:", "last: 1"])
  assert_eq(at(at(d, "server"), "port").as_number(), 8080.0)
  assert_eq(at(at(d, "server"), "hosts").as_array().len(), 2)
  assert_eq(at(d, "tags").as_array()[1].as_string(), "y")
  assert(at(d, "empty").is_null())
  assert_eq(at(d, "last").as_number(), 1.0)
end

fun test_sequences_of_mappings()
  let d = doc(["users:", "  - name: ada", "    admin: true", "  - name: bob", "    roles:", "      - dev", "      - ops", "  - - 1", "    - 2"])
  let users = at(d, "users").as_array()
  assert_eq(users.len(), 3)
  assert_eq(at(users[0], "name").as_string(), "ada")
  assert_eq(at(users[0], "admin").as_bool(), true)
  assert_eq(at(users[1], "roles").as_array().len(), 2)
  assert_eq(users[2].as_array().len(), 2)
end

fun test_flow_collections_and_comments()
  let d = doc(["# a comment", "a: [1, 2, [3, 4]]  # trailing", "b: \{x: 1, y: 'two', z: [a, b]\}", "c: \"has # inside\"", "d: [", "  one,", "  two", "]"])
  assert_eq(at(d, "a").as_array()[2].as_array().len(), 2)
  assert_eq(at(at(d, "b"), "y").as_string(), "two")
  assert_eq(at(at(d, "b"), "z").as_array().len(), 2)
  assert_eq(at(d, "c").as_string(), "has # inside")
  assert_eq(at(d, "d").as_array()[1].as_string(), "two")
end

fun test_block_scalars()
  let d = doc(["lit: |", "  line one", "  line two", "", "folded: >", "  one", "  two", "", "  three", "strip: |-", "  no newline", "keep: |+", "  kept", "", "after: 1"])
  assert_eq(at(d, "lit").as_string(), "line one\nline two\n")
  assert_eq(at(d, "folded").as_string(), "one two\nthree\n")
  assert_eq(at(d, "strip").as_string(), "no newline")
  assert_eq(at(d, "keep").as_string(), "kept\n\n")
  assert_eq(at(d, "after").as_number(), 1.0)
end

fun test_documents()
  let all = assert_ok(yaml.parse_all("---\na: 1\n---\nb: 2\n"))
  assert_eq(all.len(), 2)
  assert_eq(at(all[1], "b").as_number(), 2.0)
  assert(assert_ok(yaml.parse("")).is_null())
  assert_eq(at(assert_ok(yaml.parse("--- \nk: v\n")), "k").as_string(), "v")
end

fun test_what_it_cannot_read_is_said()
  assert(yaml.parse("a: &x 1\nb: *x\n").is_err())
  assert(yaml.parse("a: !!str 1\n").is_err())
  assert(yaml.parse("a: 1\na: 2\n").is_err())
  assert(yaml.parse("a:\n\tb: 1\n").is_err())
  assert(yaml.parse("a: [1, 2\n").is_err())
  assert(yaml.parse("a: \"open\n").is_err())
  let e = yaml.parse("a: 1\n b: 2\n")
  assert(e.is_err())
  assert(e.unwrap_err().message.contains("line 2"))
end

fun test_dump_reads_back_the_same()
  let original = doc(["name: qlang", "version: '1.0'", "ports:", "  - 80", "  - 443", "nested:", "  deep:", "    list:", "      - a: 1", "        b: two", "      - plain", "empty_list: []", "empty_map: \{\}", "note: 'a: b'", "none: ~", "flag: false", "text: \"multi\\nline\""])
  let written = yaml.dump(original)
  assert_eq(assert_ok(yaml.parse(written)).to_text(), original.to_text())
  assert(written.contains("version: \"1.0\""))
  assert(written.contains("- a: 1"))
end

import "template.q" as template

-- JSON for the tests: `<<` and `>>` stand for the braces, which a qlang string cannot hold bare
fun data(text: string) -> Json
  assert_ok(Json.parse(text.replace("<<", "\{").replace(">>", "}")))
end

fun test_values_and_paths()
  let d = data("<<\"name\": \"Ana\", \"user\": <<\"city\": \"Lyon\">>, \"items\": [\"a\", \"b\"], \"n\": 3, \"pi\": 3.5>>")
  assert_eq(assert_ok(template.render("Hello \{\{ name }}!", d)), "Hello Ana!")
  assert_eq(assert_ok(template.render("\{\{user.city}} \{\{ items.1 }} \{\{ n }} \{\{ pi }}", d)), "Lyon b 3 3.5")
  assert_eq(assert_ok(template.render("no tags", d)), "no tags")
  assert_eq(assert_ok(template.render("", d)), "")
end

fun test_string_literals_and_filters()
  let d = data("<<\"name\": \"  ana  \">>")
  assert_eq(assert_ok(template.render("\{\{ name | trim | upper }}", d)), "ANA")
  assert_eq(assert_ok(template.render("\{\{ name | trim | capitalize }}", d)), "Ana")
  assert_eq(assert_ok(template.render("\{\{ name | len }}", d)), "7")
  assert_eq(assert_ok(template.render("\{\{ \"\{\{\" }}", d)), "\{\{")
  assert_eq(assert_ok(template.render("\{\{ \"x\" | upper }}", d)), "X")
end

fun test_if_else_and_not()
  let d = data("<<\"yes\": true, \"no\": false, \"empty\": \"\", \"list\": []>>")
  assert_eq(assert_ok(template.render("\{% if yes %}A\{% else %}B\{% end %}", d)), "A")
  assert_eq(assert_ok(template.render("\{% if no %}A\{% else %}B\{% end %}", d)), "B")
  assert_eq(assert_ok(template.render("\{% if empty %}A\{% end %}|\{% if list %}B\{% end %}|\{% if missing %}C\{% end %}", d)), "||")
  assert_eq(assert_ok(template.render("\{% if not no %}A\{% end %}", d)), "A")
  assert_eq(assert_ok(template.render("\{% if yes %}x\{% if no %}y\{% else %}z\{% end %}w\{% end %}", d)), "xzw")
end

fun test_for_and_loop_variables()
  let d = data("<<\"items\": [\"a\", \"b\", \"c\"], \"people\": [<<\"n\": \"Ana\">>, <<\"n\": \"Bob\">>]>>")
  assert_eq(assert_ok(template.render("\{% for x in items %}[\{\{ x }}]\{% end %}", d)), "[a][b][c]")
  assert_eq(assert_ok(template.render("\{% for x in items %}\{\{ loop.index }}\{% if loop.last %}.\{% else %},\{% end %}\{% end %}", d)), "1,2,3.")
  assert_eq(assert_ok(template.render("\{% for p in people %}\{\{ p.n }};\{% end %}", d)), "Ana;Bob;")
  assert_eq(assert_ok(template.render("\{% for x in missing %}never\{% end %}ok", d)), "ok")
  assert_eq(assert_ok(template.render("\{% for x in items %}\{% for y in items %}\{\{ x }}\{\{ y }} \{% end %}\{% end %}", d)).len(), 27)
end

fun test_comments_and_lines()
  let d = data("<<\"a\": 1>>")
  assert_eq(assert_ok(template.render("x\{# nothing\nhere #}y\{\{ a }}", d)), "xy1")
end

fun test_html_escaping()
  let d = data("<<\"t\": \"<b>\\\"hi\\\" & 'bye'</b>\">>")
  assert_eq(assert_ok(template.render_html("\{\{ t }}", d)), "&lt;b&gt;&quot;hi&quot; &amp; &#39;bye&#39;&lt;/b&gt;")
  assert_eq(assert_ok(template.render_html("\{\{ t | raw }}", d)), "<b>\"hi\" & 'bye'</b>")
  assert_eq(assert_ok(template.render("\{\{ t }}", d)), "<b>\"hi\" & 'bye'</b>")
  assert_eq(assert_ok(template.render("\{\{ t | escape }}", d)), "&lt;b&gt;&quot;hi&quot; &amp; &#39;bye&#39;&lt;/b&gt;")
end

fun test_plain_text_values()
  assert_eq(assert_ok(template.render_text("Dear \{\{ who }},", { "who": "Ana" })), "Dear Ana,")
end

fun test_errors_say_what_and_where()
  let d = data("<<\"a\": 1, \"list\": [1], \"o\": <<>>>>")
  let missing = assert_err(template.render("line one\n\{\{ nope }}", d))
  assert_contains_text(missing.message, "`nope` is not defined")
  assert_contains_text(missing.message, "line 2")
  assert_contains_text(assert_err(template.render("\{\{ a", d)).message, "never closed")
  assert_contains_text(assert_err(template.render("\{% if a %}x", d)).message, "no `end`")
  assert_contains_text(assert_err(template.render("\{% end %}", d)).message, "without a matching")
  assert_contains_text(assert_err(template.render("\{% sing a %}", d)).message, "unknown tag")
  assert_contains_text(assert_err(template.render("\{\{ a | shout }}", d)).message, "unknown filter")
  assert_contains_text(assert_err(template.render("\{\{ list }}", d)).message, "cannot be printed")
  assert_contains_text(assert_err(template.render("\{% for x in a %}\{% end %}", d)).message, "not a list")
  assert_contains_text(assert_err(template.render("\{% for x a %}\{% end %}", d)).message, "write `for name in items`")
  assert_contains_text(assert_err(template.render("\{\{ }}", d)).message, "empty")
end

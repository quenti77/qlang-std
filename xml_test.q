import "xml.q" as xml

fun doc(text: string) -> xml.XmlNode
  assert_ok(xml.parse(text))
end

fun test_elements_attributes_and_text()
  let d = doc("<?xml version=\"1.0\"?>\n<!-- c --><feed lang='fr'><item id=\"1\">One</item><item id=\"2\"/>tail</feed>")
  assert_eq(d.name, "feed")
  assert_eq(d.attrs["lang"], "fr")
  assert_eq(d.children.len(), 2)
  assert_eq(d.children[0].text, "One")
  assert_eq(d.children[1].attrs["id"], "2")
  assert_eq(d.text, "tail")
  assert_eq(d.deep_text(), "tailOne")
end

fun test_entities_cdata_and_comments_inside()
  let d = doc("<a>x &lt; y &amp; &#65;&#x42; <![CDATA[<raw & text>]]><!-- skipped --> end</a>")
  assert_eq(d.text, "x < y & AB <raw & text> end")
  let q = doc("<a t=\"say &quot;hi&quot; &amp; bye\"/>")
  assert_eq(q.attrs["t"], "say \"hi\" & bye")
end

fun test_a_doctype_defines_nothing()
  let ok = doc("<!DOCTYPE note [<!ENTITY a \"b\">]><note>text</note>")
  assert_eq(ok.text, "text")
  assert(xml.parse("<!DOCTYPE note [<!ENTITY a \"b\">]><note>&a;</note>").is_err())
end

fun test_errors_say_the_line()
  assert(xml.parse("").is_err())
  assert(xml.parse("<a><b></a>").is_err())
  assert(xml.parse("<a>").is_err())
  assert(xml.parse("<a/><b/>").is_err())
  assert(xml.parse("<a x=1/>").is_err())
  assert(xml.parse("<a x=\"1\" x=\"2\"/>").is_err())
  assert(xml.parse("<a>&;</a>").is_err())
  let e = xml.parse("<a>\n<b>\n</a>")
  assert(e.is_err())
  assert(e.unwrap_err().message.contains("line 3"))
  assert(xml.parse("<a>".repeat(300)).is_err())
end

fun test_writing_escapes_and_reads_back()
  let d = doc("<r a=\"x &amp; &quot;y&quot;\"><c>1 &lt; 2</c><e/></r>")
  let text = xml.to_text(d)
  assert_eq(text, "<r a=\"x &amp; &quot;y&quot;\"><c>1 &lt; 2</c><e/></r>")
  assert_eq(xml.to_text(doc(text)), text)
  let pretty = xml.write_pretty(d)
  assert(pretty.starts_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<r"))
  assert(pretty.contains("\n  <c>1 &lt; 2</c>\n"))
  assert_eq(xml.to_text(doc(pretty)).contains("<c>1 &lt; 2</c>"), true)
end

fun names(nodes: array<xml.XmlNode>) -> array<string>
  nodes.map(fun(n: xml.XmlNode) -> string n.name + ":" + (n.attrs["id"] ?? "") end)
end

fun test_xpath_selects_nodes()
  let d = doc("<lib><shelf id=\"a\"><book id=\"1\">One</book><book id=\"2\">Two</book></shelf><shelf id=\"b\"><book id=\"3\">Three</book></shelf></lib>")
  assert_eq(names(assert_ok(xml.select(d, "/lib/shelf"))), ["shelf:a", "shelf:b"])
  assert_eq(names(assert_ok(xml.select(d, "shelf/book"))), ["book:1", "book:2", "book:3"])
  assert_eq(names(assert_ok(xml.select(d, "//book"))), ["book:1", "book:2", "book:3"])
  assert_eq(names(assert_ok(xml.select(d, "//shelf[@id='b']/book"))), ["book:3"])
  assert_eq(names(assert_ok(xml.select(d, "/lib/shelf[2]/book"))), ["book:3"])
  assert_eq(names(assert_ok(xml.select(d, "shelf[1]/book[last()]"))), ["book:2"])
  assert_eq(names(assert_ok(xml.select(d, "shelf/*[@id]"))), ["book:1", "book:2", "book:3"])
  assert_eq(assert_ok(xml.select(d, "/other")).len(), 0)
  assert_eq(assert_some(xml.first(d, "//book[@id='2']")).text, "Two")
  assert(xml.first(d, "//nothing") == none)
end

fun test_xpath_values_and_errors()
  let d = doc("<lib><book id=\"1\">One</book><book id=\"2\">Two</book></lib>")
  assert_eq(assert_ok(xml.values(d, "//book/@id")), ["1", "2"])
  assert_eq(assert_ok(xml.values(d, "//book[@id='2']/text()")), ["Two"])
  assert_eq(assert_ok(xml.values(d, "book")), ["One", "Two"])
  assert(xml.select(d, "//book/@id").is_err())
  assert(xml.select(d, "book[").is_err())
  assert(xml.select(d, "book[@id=1]").is_err())
  assert(xml.select(d, "").is_err())
end

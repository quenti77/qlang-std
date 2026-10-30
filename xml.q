--" # XML

Reads XML into a tree of `XmlNode`s, writes a tree as XML text, and finds nodes with a simple
XPath.

```
import "@std/xml.q" as xml

let doc = xml.parse("<feed><item id=\"1\">One</item><item id=\"2\">Two</item></feed>").unwrap()
for item in xml.select(doc, "/feed/item") do
  print("{item.attrs["id"] ?? ""}: {item.text}")
end
print(xml.values(doc, "//item[@id='2']/text()"))     -- ["Two"]
print(xml.to_text(doc))
```

What is read: elements, attributes (single or double quotes), text, `<![CDATA[...]]>` (as text),
the five predefined entities and `&#65;` / `&#x41;`, comments and processing instructions (skipped,
`<?xml ...?>` included). Names are kept as written (`atom:link`: no namespace resolution). A
`<!DOCTYPE>` is skipped and **its entities are not defined** (an `&custom;` is an error), so a document
cannot expand into gigabytes or read a file. The depth is limited to 200.

`XmlNode.text` is the text written directly inside the element (the pieces around its children,
put together); `deep_text()` adds the text of the descendants.

The XPath is the useful part: `/a/b` from the root, `a/b` from a node, `//b` anywhere below, `*` for
any name, `.`, and on a step a predicate: `[@id]` (has the attribute), `[@id='x']`, `[2]` (the second,
counting from 1), `[last()]`. A final `@id` or `text()` gives the texts (`values`).
--"

struct XmlNode
  public name: string
  public attrs: map<string, string>
  public children: array<XmlNode>
  public text: string
end

impl XmlNode
  --" A node without attributes, children or text. --"
  public fun element(name: string) -> XmlNode
    XmlNode { name: name, attrs: {}, children: [], text: "" }
  end

  --" The text of the element and of all its descendants, in order of reading. --"
  public fun deep_text(self) -> string
    let out = self.text
    for c in self.children do
      out += c.deep_text()
    end
    out
  end

  --" The first child with this name. --"
  public fun child(self, name: string) -> XmlNode?
    for c in self.children do
      if c.name == name then
        return c
      end
    end
    none
  end
end

struct Reader
  public chars: array<string>
  public pos: int
end

impl Reader
  public fun more(self) -> bool
    self.pos < self.chars.len()
  end

  public fun peek(self) -> string
    if self.more() then self.chars[self.pos] else "" end
  end

  public fun looking_at(self, text: string) -> bool
    let n = text.len()
    if self.pos + n > self.chars.len() then
      return false
    end
    self.chars.slice(self.pos, self.pos + n).join("") == text
  end

  public fun skip_space(self)
    while self.more() and (self.peek() == " " or self.peek() == "\n" or self.peek() == "\t" or self.peek() == "\r") do
      self.pos += 1
    end
  end

  public fun line(self) -> int
    let n = 1
    for i in 0..self.pos do
      if self.chars[i] == "\n" then
        n += 1
      end
    end
    n
  end
end

fun fail<T>(r: Reader, message: string) -> Result<T, Error>
  Err(Error { message: "line {r.line()}: {message}" })
end

fun is_name_char(c: string) -> bool
  c != "" and (c.is_alpha() or c.is_digit() or c == "_" or c == "-" or c == "." or c == ":")
end

fun read_name(r: Reader) -> Result<string, Error>
  let name = ""
  while r.more() and is_name_char(r.peek()) do
    name += r.peek()
    r.pos += 1
  end
  if name == "" then
    return fail<string>(r, "expected a name")
  end
  Ok(name)
end

fun hex_value(text: string) -> int?
  let n = 0
  for c in text.chars() do
    let d = "0123456789abcdef".index_of(c.lower())
    if d == none then
      return none
    end
    n = n * 16 + d
  end
  n
end

-- the text with `&...;` replaced
fun decode(r: Reader, raw: string) -> Result<string, Error>
  if not raw.contains("&") then
    return Ok(raw)
  end
  let out = ""
  let rest = raw
  while true do
    let at = rest.index_of("&")
    if at == none then
      out += rest
      break
    end
    out += rest.substring(0, at)
    let semi = rest.index_of(";")
    if semi == none or semi < at then
      return fail<string>(r, "an `&` is not closed by `;` (write `&amp;`)")
    end
    let name = rest.substring(at + 1, semi)
    if name == "lt" then
      out += "<"
    elseif name == "gt" then
      out += ">"
    elseif name == "amp" then
      out += "&"
    elseif name == "quot" then
      out += "\""
    elseif name == "apos" then
      out += "'"
    elseif name.starts_with("#x") or name.starts_with("#X") then
      let code = hex_value(name.substring(2, name.len()))
      if code == none or code > 1114111 or code == 0 then
        return fail<string>(r, "`&{name};` is not a character")
      end
      out += code.char()
    elseif name.starts_with("#") then
      let code = int.parse(name.substring(1, name.len()))
      if code == none or code > 1114111 or code <= 0 then
        return fail<string>(r, "`&{name};` is not a character")
      end
      out += code.char()
    else
      return fail<string>(r, "unknown entity `&{name};` (only the five predefined ones and numbers)")
    end
    rest = rest.substring(semi + 1, rest.len())
  end
  Ok(out)
end

-- skips up to and including `marker`
fun skip_past(r: Reader, marker: string) -> Result<bool, Error>
  while r.more() do
    if r.looking_at(marker) then
      r.pos += marker.len()
      return Ok(true)
    end
    r.pos += 1
  end
  fail<bool>(r, "`{marker}` was expected")
end

fun skip_doctype(r: Reader) -> Result<bool, Error>
  -- `<!DOCTYPE name [ ... ]>`: the brackets may hold `>`
  let depth = 0
  while r.more() do
    let c = r.peek()
    r.pos += 1
    if c == "[" then
      depth += 1
    elseif c == "]" then
      depth -= 1
    elseif c == ">" and depth <= 0 then
      return Ok(true)
    end
  end
  fail<bool>(r, "a `<!DOCTYPE` is not closed")
end

fun read_attrs(r: Reader) -> Result<map<string, string>, Error>
  let attrs: map<string, string> = {}
  while true do
    r.skip_space()
    let c = r.peek()
    if c == ">" or c == "/" or c == "" then
      break
    end
    let name = read_name(r)?
    r.skip_space()
    if r.peek() != "=" then
      return fail<map<string, string>>(r, "the attribute `{name}` has no value")
    end
    r.pos += 1
    r.skip_space()
    let q = r.peek()
    if q != "\"" and q != "'" then
      return fail<map<string, string>>(r, "the value of `{name}` must be in quotes")
    end
    r.pos += 1
    let raw = ""
    while r.more() and r.peek() != q do
      raw += r.peek()
      r.pos += 1
    end
    if not r.more() then
      return fail<map<string, string>>(r, "the value of `{name}` is not closed")
    end
    r.pos += 1
    if attrs[name] != none then
      return fail<map<string, string>>(r, "the attribute `{name}` is there twice")
    end
    attrs[name] = decode(r, raw)?
  end
  Ok(attrs)
end

fun read_element(r: Reader, depth: int) -> Result<XmlNode, Error>
  if depth > 200 then
    return fail<XmlNode>(r, "elements are nested too deep (200)")
  end
  r.pos += 1
  let name = read_name(r)?
  let attrs = read_attrs(r)?
  let node = XmlNode { name: name, attrs: attrs, children: [], text: "" }
  if r.peek() == "/" then
    r.pos += 1
    if r.peek() != ">" then
      return fail<XmlNode>(r, "expected `>`")
    end
    r.pos += 1
    return Ok(node)
  end
  if r.peek() != ">" then
    return fail<XmlNode>(r, "the tag `{name}` is not closed")
  end
  r.pos += 1
  let raw = ""
  while true do
    if not r.more() then
      return fail<XmlNode>(r, "`<{name}>` is never closed")
    end
    if r.looking_at("</") then
      r.pos += 2
      let closing = read_name(r)?
      r.skip_space()
      if r.peek() != ">" then
        return fail<XmlNode>(r, "expected `>`")
      end
      r.pos += 1
      if closing != name then
        return fail<XmlNode>(r, "`</{closing}>` closes `<{name}>`")
      end
      break
    elseif r.looking_at("<!--") then
      r.pos += 4
      skip_past(r, "-->")?
    elseif r.looking_at("<![CDATA[") then
      r.pos += 9
      let cdata = ""
      while r.more() and not r.looking_at("]]>") do
        cdata += r.peek()
        r.pos += 1
      end
      if not r.more() then
        return fail<XmlNode>(r, "a CDATA section is not closed")
      end
      r.pos += 3
      node.text += decode_pending(r, raw)? + cdata
      raw = ""
    elseif r.looking_at("<?") then
      r.pos += 2
      skip_past(r, "?>")?
    elseif r.peek() == "<" then
      node.text += decode_pending(r, raw)?
      raw = ""
      node.children.push(read_element(r, depth + 1)?)
    else
      raw += r.peek()
      r.pos += 1
    end
  end
  node.text += decode_pending(r, raw)?
  Ok(node)
end

fun decode_pending(r: Reader, raw: string) -> Result<string, Error>
  decode(r, raw)
end

--" Reads an XML document and gives its root element. `err` says the line of what it cannot read. --"
fun parse(text: string) -> Result<XmlNode, Error>
  let r = Reader { chars: text.chars(), pos: 0 }
  if r.peek() == 65279.char() then
    r.pos += 1
  end
  while true do
    r.skip_space()
    if not r.more() then
      return fail<XmlNode>(r, "there is no element")
    end
    if r.looking_at("<?") then
      r.pos += 2
      skip_past(r, "?>")?
    elseif r.looking_at("<!--") then
      r.pos += 4
      skip_past(r, "-->")?
    elseif r.looking_at("<!DOCTYPE") then
      skip_doctype(r)?
    elseif r.peek() == "<" then
      break
    else
      return fail<XmlNode>(r, "text outside of the root element")
    end
  end
  let root = read_element(r, 0)?
  while true do
    r.skip_space()
    if not r.more() then
      break
    end
    if r.looking_at("<!--") then
      r.pos += 4
      skip_past(r, "-->")?
    elseif r.looking_at("<?") then
      r.pos += 2
      skip_past(r, "?>")?
    else
      return fail<XmlNode>(r, "more than one root element, or text after it")
    end
  end
  Ok(root)
end

-- ------------------------------------------------------------------------ writing

fun escape_text(s: string) -> string
  s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
end

fun escape_attr(s: string) -> string
  escape_text(s).replace("\"", "&quot;").replace("\n", "&#10;").replace("\t", "&#9;")
end

fun write_into(n: XmlNode, depth: int, pretty: bool, out: array<string>)
  let pad = if pretty then "  ".repeat(depth) else "" end
  let tag = n.name
  for k in n.attrs.keys() do
    tag += " {k}=\"{escape_attr(n.attrs[k] ?? "")}\""
  end
  if n.children.is_empty() and n.text == "" then
    out.push("{pad}<{tag}/>")
    return
  end
  if n.children.is_empty() then
    out.push("{pad}<{tag}>{escape_text(n.text)}</{n.name}>")
    return
  end
  out.push("{pad}<{tag}>")
  if n.text != "" and (n.text.trim() != "" or not pretty) then
    out.push("{pad}{if pretty then "  " else "" end}{escape_text(n.text)}")
  end
  for c in n.children do
    write_into(c, depth + 1, pretty, out)
  end
  out.push("{pad}</{n.name}>")
end

--" The tree as XML text on one line, with the escapes needed (`&amp;`, `&lt;`...). Text that sits
between children is gathered where the first child begins, since a node keeps its text as one piece. --"
fun to_text(n: XmlNode) -> string
  let out: array<string> = []
  write_into(n, 0, false, out)
  out.join("")
end

--" Like `to_text`, one element per line, two spaces per level, with the `<?xml ...?>` line first. --"
fun write_pretty(n: XmlNode) -> string
  let out: array<string> = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
  write_into(n, 0, true, out)
  out.join("\n") + "\n"
end

-- ------------------------------------------------------------------------ XPath

struct Step
  public descendant: bool
  public name: string
  public attr: string
  public attr_value: string?
  public index: int
  public last: bool
end

fun parse_step(text: string, descendant: bool) -> Result<Step, Error>
  let one = Step { descendant: descendant, name: text, attr: "", attr_value: none, index: 0, last: false }
  let open = text.index_of("[")
  if open == none then
    return Ok(one)
  end
  if not text.ends_with("]") then
    return Err(Error { message: "xpath: `{text}`: a `[` is not closed" })
  end
  one.name = text.substring(0, open)
  let predicate = text.substring(open + 1, text.len() - 1).trim()
  if predicate.starts_with("@") then
    let eq = predicate.index_of("=")
    if eq == none then
      one.attr = predicate.substring(1, predicate.len())
    else
      one.attr = predicate.substring(1, eq).trim()
      let v = predicate.substring(eq + 1, predicate.len()).trim()
      if v.len() < 2 or not ((v.starts_with("'") and v.ends_with("'")) or (v.starts_with("\"") and v.ends_with("\""))) then
        return Err(Error { message: "xpath: `{text}`: the value must be in quotes" })
      end
      one.attr_value = v.substring(1, v.len() - 1)
    end
    return Ok(one)
  end
  if predicate == "last()" then
    one.last = true
    return Ok(one)
  end
  let n = int.parse(predicate)
  if n == none or n < 1 then
    return Err(Error { message: "xpath: `{text}`: a predicate is `@a`, `@a='v'`, a number from 1, or `last()`" })
  end
  one.index = n
  Ok(one)
end

fun split_path(path: string) -> Result<array<Step>, Error>
  let steps: array<Step> = []
  let rest = path.trim()
  if rest == "" then
    return Err(Error { message: "xpath: the path is empty" })
  end
  let first = true
  while rest != "" do
    let descendant = false
    if rest.starts_with("//") then
      descendant = true
      rest = rest.substring(2, rest.len())
    elseif rest.starts_with("/") then
      rest = rest.substring(1, rest.len())
    elseif not first then
      return Err(Error { message: "xpath: `{path}` is not a path" })
    end
    first = false
    -- a step ends at the next `/` that is not inside brackets
    let depth = 0
    let cut = rest.len()
    let i = 0
    for c in rest.chars() do
      if c == "[" then
        depth += 1
      elseif c == "]" then
        depth -= 1
      elseif c == "/" and depth == 0 then
        cut = i
        break
      end
      i += 1
    end
    steps.push(parse_step(rest.substring(0, cut), descendant)?)
    rest = rest.substring(cut, rest.len())
  end
  Ok(steps)
end

fun below(n: XmlNode, out: array<XmlNode>)
  for c in n.children do
    out.push(c)
    below(c, out)
  end
end

fun matches_step(n: XmlNode, s: Step) -> bool
  if s.name != "*" and n.name != s.name then
    return false
  end
  if s.attr != "" then
    let v = n.attrs[s.attr]
    if v == none then
      return false
    end
    if s.attr_value != none and v != s.attr_value then
      return false
    end
  end
  true
end

fun apply_step(current: array<XmlNode>, s: Step, first_absolute: bool, root: XmlNode) -> array<XmlNode>
  let found: array<XmlNode> = []
  for n in current do
    let candidates: array<XmlNode> = []
    if s.descendant then
      candidates.push(n)
      below(n, candidates)
      if not first_absolute then
        -- below the node, not the node itself (`//a` from the root also matches the root)
        candidates.remove(0)
      end
    elseif first_absolute then
      candidates.push(n)
    else
      for c in n.children do
        candidates.push(c)
      end
    end
    let hits: array<XmlNode> = []
    for c in candidates do
      if matches_step(c, s) then
        hits.push(c)
      end
    end
    if s.index > 0 then
      if hits.len() >= s.index then
        found.push(hits[s.index - 1])
      end
    elseif s.last then
      if hits.len() > 0 then
        found.push(hits[hits.len() - 1])
      end
    else
      for h in hits do
        found.push(h)
      end
    end
  end
  found
end

-- the nodes the steps lead to, and the last step if it asks for text or an attribute
fun run_path(node: XmlNode, path: string) -> Result<(array<XmlNode>, string), Error>
  let p = path.trim()
  if p == "" then
    return Err(Error { message: "xpath: the path is empty" })
  end
  let tail = ""
  let body = p
  if p.ends_with("/text()") then
    tail = "text()"
    body = p.substring(0, p.len() - 7)
  else
    let slash = p.last_index_of("/")
    if slash != none and p.substring(slash + 1, p.len()).starts_with("@") then
      tail = p.substring(slash + 1, p.len())
      body = p.substring(0, slash)
    end
  end
  let nodes: array<XmlNode> = [node]
  if body == "" or body == "." then
    return Ok((nodes, tail))
  end
  let absolute = body.starts_with("/")
  let steps = split_path(body)?
  let first = true
  for s in steps do
    nodes = apply_step(nodes, s, absolute and first, node)
    first = false
  end
  Ok((nodes, tail))
end

--" The elements a path leads to. `/feed/item` starts from the root element you give (its name is
the first step); `item/title` starts below it; `//title` is every `title` below (and the node itself
when the path is absolute). `err` for a path that is not valid. --"
fun select(node: XmlNode, path: string) -> Result<array<XmlNode>, Error>
  if path.trim().ends_with("/text()") or path.contains("/@") then
    return Err(Error { message: "xpath: `{path}` gives texts: use `values`" })
  end
  let r = run_path(node, path)?
  Ok(r.0)
end

--" The first element a path leads to, or `none`. --"
fun first(node: XmlNode, path: string) -> XmlNode?
  let r = select(node, path)
  if r.is_err() or r.unwrap().is_empty() then
    return none
  end
  r.unwrap()[0]
end

--" The texts a path leads to: the attribute of `.../@id`, the text of `.../text()`, or, for a path
to elements, their whole text (`deep_text`). --"
fun values(node: XmlNode, path: string) -> Result<array<string>, Error>
  let r = run_path(node, path)?
  let out: array<string> = []
  for n in r.0 do
    if r.1 == "text()" then
      out.push(n.text)
    elseif r.1.starts_with("@") then
      let v = n.attrs[r.1.substring(1, r.1.len())]
      if v != none then
        out.push(v)
      end
    else
      out.push(n.deep_text())
    end
  end
  Ok(out)
end

export XmlNode, parse, to_text, write_pretty, select, first, values

--" # YAML

Reads the YAML of configuration files into a `Json` value, and writes a `Json` value as YAML.

```
import "@std/yaml.q" as yaml

let config = yaml.parse("server:\n  port: 8080\n  hosts: [a, b]\n").unwrap()
let port = config.get("server").unwrap().get("port").unwrap().as_number()   -- 8080.0
print(yaml.dump(config))
```

What is read: block mappings and sequences (by indentation, `- key: value` included), flow
collections `[a, b]` and `{a: 1}` (on several lines too), plain, `'single'` and `"double"` quoted
scalars, block scalars (`|` literal and `>` folded, with `-` and `+`), comments, and a leading `---`.
Plain scalars follow the YAML 1.2 core schema: `null`, `~` and nothing are `null`; `true` and `false`
are booleans; integers and floats are numbers (`yes`/`no` are text); everything else is text.

What is **not** read, with an error that says so: anchors and aliases (`&a`, `*a`), tags (`!!str`),
merge keys (`<<`), complex keys (`? `), tabs for indentation, and a document after the first one
(`parse_all` reads them all). Numbers are `float`s, so an integer beyond 2^53 loses its last digits.
--"

struct Doc
  public lines: array<string>
  public pos: int
end

fun fail<T>(doc: Doc, message: string) -> Result<T, Error>
  Err(Error { message: "line {doc.pos + 1}: {message}" })
end

fun indent_of(line: string) -> int
  let n = 0
  for c in line.chars() do
    if c == " " then
      n += 1
    else
      break
    end
  end
  n
end

fun is_blank(line: string) -> bool
  let t = line.trim()
  t == "" or t.starts_with("#")
end

-- moves to the next line that carries something (a comment or an empty line carries nothing)
fun skip_blank(doc: Doc)
  while doc.pos < doc.lines.len() and is_blank(doc.lines[doc.pos]) do
    doc.pos += 1
  end
end

fun at_end(doc: Doc) -> bool
  doc.pos >= doc.lines.len()
end

-- ------------------------------------------------------------------------ scalars

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

fun plain_scalar(text: string) -> Json
  if text == "" or text == "~" or text == "null" or text == "Null" or text == "NULL" then
    return Json.null()
  end
  if text == "true" or text == "True" or text == "TRUE" then
    return Json.boolean(true)
  end
  if text == "false" or text == "False" or text == "FALSE" then
    return Json.boolean(false)
  end
  if text == ".inf" or text == ".Inf" or text == "+.inf" then
    return Json.number(float.INFINITY)
  end
  if text == "-.inf" or text == "-.Inf" then
    return Json.number(-float.INFINITY)
  end
  if text == ".nan" or text == ".NaN" then
    return Json.number(float.NAN)
  end
  if regex.matches(text, "^[-+]?[0-9]+$") then
    let n = text.to_float()
    if n != none then
      return Json.number(n)
    end
  end
  if text.starts_with("0x") and text.len() > 2 then
    let n = hex_value(text.substring(2, text.len()))
    if n != none then
      return Json.number(n as float)
    end
  end
  if regex.matches(text, "^[-+]?([0-9]+[.][0-9]*|[.][0-9]+|[0-9]+)([eE][-+]?[0-9]+)?$") then
    let n = text.to_float()
    if n != none then
      return Json.number(n)
    end
  end
  Json.string(text)
end

-- the end of the text before a ` #` comment, outside quotes
fun strip_comment(text: string) -> string
  let quote = ""
  let prev = " "
  let i = 0
  let chars = text.chars()
  while i < chars.len() do
    let c = chars[i]
    if quote == "" then
      if (c == "\"" or c == "'") and (prev == " " or prev == "[" or prev == "\{" or prev == ",") then
        quote = c
      elseif c == "#" and prev == " " then
        return text.substring(0, i).trim()
      end
    else
      if c == "\\" and quote == "\"" then
        i += 1
      elseif c == quote then
        if quote == "'" and i + 1 < chars.len() and chars[i + 1] == "'" then
          i += 1
        else
          quote = ""
        end
      end
    end
    prev = c
    i += 1
  end
  text.trim()
end

struct Cursor
  public chars: array<string>
  public pos: int
  public doc: Doc
end

impl Cursor
  public fun more(self) -> bool
    self.pos < self.chars.len()
  end

  public fun peek(self) -> string
    if self.more() then self.chars[self.pos] else "" end
  end

  public fun skip_space(self)
    while self.more() and (self.peek() == " " or self.peek() == "\t") do
      self.pos += 1
    end
  end
end

fun double_quoted(cur: Cursor) -> Result<string, Error>
  cur.pos += 1
  let out = ""
  while cur.more() do
    let c = cur.peek()
    cur.pos += 1
    if c == "\"" then
      return Ok(out)
    end
    if c != "\\" then
      out += c
      continue
    end
    let e = cur.peek()
    cur.pos += 1
    if e == "n" then
      out += "\n"
    elseif e == "t" then
      out += "\t"
    elseif e == "r" then
      out += "\r"
    elseif e == "0" then
      out += 0.char()
    elseif e == "e" then
      out += 27.char()
    elseif e == "b" then
      out += 8.char()
    elseif e == "f" then
      out += 12.char()
    elseif e == "\"" or e == "\\" or e == "/" or e == " " then
      out += e
    elseif e == "x" or e == "u" or e == "U" then
      let size = if e == "x" then 2 elseif e == "u" then 4 else 8 end
      let digits = ""
      for i in 0..size do
        digits += cur.peek()
        cur.pos += 1
      end
      let code = hex_value(digits)
      if code == none or code > 1114111 then
        return fail<string>(cur.doc, "`\\{e}{digits}` is not a character")
      end
      out += code.char()
    else
      return fail<string>(cur.doc, "unknown escape `\\{e}`")
    end
  end
  fail<string>(cur.doc, "a string is not closed")
end

fun single_quoted(cur: Cursor) -> Result<string, Error>
  cur.pos += 1
  let out = ""
  while cur.more() do
    let c = cur.peek()
    cur.pos += 1
    if c == "'" then
      if cur.peek() == "'" then
        out += "'"
        cur.pos += 1
      else
        return Ok(out)
      end
    else
      out += c
    end
  end
  fail<string>(cur.doc, "a string is not closed")
end

-- ------------------------------------------------------------------------ flow collections

fun flow_value(cur: Cursor) -> Result<Json, Error>
  cur.skip_space()
  let c = cur.peek()
  if c == "[" then
    cur.pos += 1
    let items: array<Json> = []
    while true do
      cur.skip_space()
      if cur.peek() == "]" then
        cur.pos += 1
        break
      end
      if not cur.more() then
        return fail<Json>(cur.doc, "a `[` is not closed")
      end
      items.push(flow_value(cur)?)
      cur.skip_space()
      if cur.peek() == "," then
        cur.pos += 1
      elseif cur.peek() != "]" then
        return fail<Json>(cur.doc, "expected `,` or `]`")
      end
    end
    return Ok(Json.array(items))
  end
  if c == "\{" then
    cur.pos += 1
    let table: map<string, Json> = {}
    while true do
      cur.skip_space()
      if cur.peek() == "\}" then
        cur.pos += 1
        break
      end
      if not cur.more() then
        return fail<Json>(cur.doc, "a `\{` is not closed")
      end
      let key = flow_key(cur)?
      cur.skip_space()
      let v = Json.null()
      if cur.peek() == ":" then
        cur.pos += 1
        v = flow_value(cur)?
      end
      if table[key] != none then
        return fail<Json>(cur.doc, "the key `{key}` is there twice")
      end
      table[key] = v
      cur.skip_space()
      if cur.peek() == "," then
        cur.pos += 1
      elseif cur.peek() != "\}" then
        return fail<Json>(cur.doc, "expected `,` or `\}`")
      end
    end
    return Ok(Json.object(table))
  end
  if c == "\"" then
    return Ok(Json.string(double_quoted(cur)?))
  end
  if c == "'" then
    return Ok(Json.string(single_quoted(cur)?))
  end
  if c == "&" or c == "*" or c == "!" then
    return fail<Json>(cur.doc, "anchors, aliases and tags are not supported")
  end
  let text = ""
  while cur.more() do
    let d = cur.peek()
    if d == "," or d == "]" or d == "\}" then
      break
    end
    if d == ":" and (cur.pos + 1 >= cur.chars.len() or cur.chars[cur.pos + 1] == " ") then
      break
    end
    text += d
    cur.pos += 1
  end
  Ok(plain_scalar(text.trim()))
end

fun flow_key(cur: Cursor) -> Result<string, Error>
  cur.skip_space()
  let c = cur.peek()
  if c == "\"" then
    return double_quoted(cur)
  end
  if c == "'" then
    return single_quoted(cur)
  end
  let text = ""
  while cur.more() do
    let d = cur.peek()
    if d == "," or d == "\}" or (d == ":" and (cur.pos + 1 >= cur.chars.len() or cur.chars[cur.pos + 1] == " ")) then
      break
    end
    text += d
    cur.pos += 1
  end
  Ok(text.trim())
end

fun brackets_open(text: string) -> int
  let depth = 0
  let quote = ""
  for c in text.chars() do
    if quote != "" then
      if c == quote then
        quote = ""
      end
    elseif c == "\"" or c == "'" then
      quote = c
    elseif c == "[" or c == "\{" then
      depth += 1
    elseif c == "]" or c == "\}" then
      depth -= 1
    end
  end
  depth
end

-- ------------------------------------------------------------------------ values on one line

-- a value written after `key:` or `- `; a flow collection may go on over the next lines
fun inline_value(doc: Doc, text: string) -> Result<Json, Error>
  let t = strip_comment(text)
  if t.starts_with("&") or t.starts_with("*") or t.starts_with("!") then
    return fail<Json>(doc, "anchors, aliases and tags are not supported")
  end
  if t.starts_with("[") or t.starts_with("\{") then
    while brackets_open(t) > 0 and doc.pos + 1 < doc.lines.len() do
      doc.pos += 1
      t += " " + strip_comment(doc.lines[doc.pos])
    end
    let cur = Cursor { chars: t.chars(), pos: 0, doc: doc }
    let v = flow_value(cur)?
    cur.skip_space()
    if cur.more() then
      return fail<Json>(doc, "unexpected text after the collection")
    end
    return Ok(v)
  end
  if t.starts_with("\"") then
    let cur = Cursor { chars: t.chars(), pos: 0, doc: doc }
    let s = double_quoted(cur)?
    if cur.more() then
      return fail<Json>(doc, "unexpected text after the string")
    end
    return Ok(Json.string(s))
  end
  if t.starts_with("'") then
    let cur = Cursor { chars: t.chars(), pos: 0, doc: doc }
    let s = single_quoted(cur)?
    if cur.more() then
      return fail<Json>(doc, "unexpected text after the string")
    end
    return Ok(Json.string(s))
  end
  Ok(plain_scalar(t))
end

-- ------------------------------------------------------------------------ block scalars

-- `|` or `>` (then `-` or `+`) at `doc.pos`; the lines below that are more indented than `parent`
fun block_scalar(doc: Doc, header: string, parent: int) -> Result<Json, Error>
  let folded = header.starts_with(">")
  let chomp = ""
  for c in header.substring(1, header.len()).chars() do
    if c == "-" or c == "+" then
      chomp = c
    elseif c.is_digit() then
      return fail<Json>(doc, "an indentation indicator is not supported")
    end
  end
  doc.pos += 1
  let raw: array<string> = []
  let block = -1
  while doc.pos < doc.lines.len() do
    let line = doc.lines[doc.pos]
    if line.trim() == "" then
      raw.push("")
      doc.pos += 1
      continue
    end
    let ind = indent_of(line)
    if ind <= parent then
      break
    end
    if block < 0 then
      block = ind
    end
    if ind < block then
      break
    end
    raw.push(line.substring(block, line.len()))
    doc.pos += 1
  end
  -- empty lines at the end belong to the chomping, not to the text
  let trailing = 0
  while raw.len() > 0 and raw[raw.len() - 1] == "" do
    raw.pop()
    trailing += 1
  end
  let text = ""
  if folded then
    let i = 0
    while i < raw.len() do
      if i > 0 then
        let before = raw[i - 1]
        if raw[i] == "" then
          text += "\n"
        elseif before == "" then
          -- the empty line already gave the line break
          text += ""
        elseif raw[i].starts_with(" ") or before.starts_with(" ") then
          text += "\n"
        else
          text += " "
        end
      end
      text += raw[i]
      i += 1
    end
  else
    text = raw.join("\n")
  end
  if raw.len() == 0 then
    return Ok(Json.string(""))
  end
  if chomp == "-" then
    return Ok(Json.string(text))
  end
  if chomp == "+" then
    return Ok(Json.string(text + "\n".repeat(trailing + 1)))
  end
  Ok(Json.string(text + "\n"))
end

-- ------------------------------------------------------------------------ blocks

-- `key:` at the start of a block line: the key and what follows the colon, or none
fun split_key(text: string) -> (string, string)?
  let chars = text.chars()
  if chars.len() == 0 then
    return none
  end
  let key = ""
  let i = 0
  if chars[0] == "\"" or chars[0] == "'" then
    let q = chars[0]
    i = 1
    while i < chars.len() do
      if chars[i] == "\\" and q == "\"" then
        key += chars[i] + (if i + 1 < chars.len() then chars[i + 1] else "" end)
        i += 2
        continue
      end
      if chars[i] == q then
        break
      end
      key += chars[i]
      i += 1
    end
    i += 1
    if i >= chars.len() or chars[i] != ":" then
      return none
    end
    if i + 1 < chars.len() and chars[i + 1] != " " then
      return none
    end
    return (q + key + q, text.substring(i + 1, text.len()).trim())
  end
  if chars[0] == "[" or chars[0] == "\{" or chars[0] == "#" then
    return none
  end
  while i < chars.len() do
    if chars[i] == ":" and (i + 1 >= chars.len() or chars[i + 1] == " ") then
      return (key.trim(), text.substring(i + 1, text.len()).trim())
    end
    if chars[i] == " " and i + 1 < chars.len() and chars[i + 1] == "#" then
      return none
    end
    key += chars[i]
    i += 1
  end
  none
end

fun key_text(doc: Doc, raw: string) -> Result<string, Error>
  if raw.starts_with("\"") then
    let cur = Cursor { chars: raw.chars(), pos: 0, doc: doc }
    return double_quoted(cur)
  end
  if raw.starts_with("'") then
    let cur = Cursor { chars: raw.chars(), pos: 0, doc: doc }
    return single_quoted(cur)
  end
  if raw.starts_with("? ") or raw.starts_with("&") or raw.starts_with("*") or raw.starts_with("!") or raw == "<<" then
    return fail<string>(doc, "complex keys, anchors, tags and merge keys are not supported")
  end
  Ok(raw)
end

fun is_sequence_line(text: string) -> bool
  text == "-" or text.starts_with("- ")
end

fun parse_block(doc: Doc, min_indent: int) -> Result<Json, Error>
  skip_blank(doc)
  if at_end(doc) then
    return Ok(Json.null())
  end
  let line = doc.lines[doc.pos]
  let ind = indent_of(line)
  if ind < min_indent then
    return Ok(Json.null())
  end
  let text = line.substring(ind, line.len())
  if is_sequence_line(text) then
    return parse_sequence(doc, ind)
  end
  if split_key(text) != none then
    return parse_mapping(doc, ind)
  end
  if text.starts_with("|") or text.starts_with(">") then
    return block_scalar(doc, text.trim(), min_indent - 1)
  end
  let v = inline_value(doc, text)?
  doc.pos += 1
  Ok(v)
end

-- what follows a `key:` or a `-` that has nothing after it: the more indented lines below
fun nested(doc: Doc, parent: int, allow_same_indent_sequence: bool) -> Result<Json, Error>
  skip_blank(doc)
  if at_end(doc) then
    return Ok(Json.null())
  end
  let line = doc.lines[doc.pos]
  let ind = indent_of(line)
  if ind > parent then
    return parse_block(doc, parent + 1)
  end
  if allow_same_indent_sequence and ind == parent and is_sequence_line(line.substring(ind, line.len())) then
    return parse_sequence(doc, ind)
  end
  Ok(Json.null())
end

fun parse_mapping(doc: Doc, ind: int) -> Result<Json, Error>
  let table: map<string, Json> = {}
  while true do
    skip_blank(doc)
    if at_end(doc) then
      break
    end
    let line = doc.lines[doc.pos]
    let here = indent_of(line)
    if here < ind then
      break
    end
    if here > ind then
      return fail<Json>(doc, "unexpected indentation")
    end
    let text = line.substring(ind, line.len())
    let parts = split_key(text)
    if parts == none then
      if is_sequence_line(text) then
        break
      end
      return fail<Json>(doc, "expected `key: value`")
    end
    let key = key_text(doc, parts.0)?
    if table[key] != none then
      return fail<Json>(doc, "the key `{key}` is there twice")
    end
    let rest = parts.1
    let value = Json.null()
    let shown = strip_comment(rest)
    if shown == "" then
      doc.pos += 1
      value = nested(doc, ind, true)?
    elseif shown.starts_with("|") or shown.starts_with(">") then
      value = block_scalar(doc, shown, ind)?
    else
      value = inline_value(doc, rest)?
      doc.pos += 1
    end
    table[key] = value
  end
  Ok(Json.object(table))
end

fun parse_sequence(doc: Doc, ind: int) -> Result<Json, Error>
  let items: array<Json> = []
  while true do
    skip_blank(doc)
    if at_end(doc) then
      break
    end
    let line = doc.lines[doc.pos]
    let here = indent_of(line)
    if here < ind then
      break
    end
    if here > ind then
      return fail<Json>(doc, "unexpected indentation")
    end
    let text = line.substring(ind, line.len())
    if not is_sequence_line(text) then
      break
    end
    let after = text.substring(1, text.len())
    let rest = after.trim_start()
    if strip_comment(rest) == "" then
      doc.pos += 1
      items.push(nested(doc, ind, false)?)
    elseif rest.starts_with("|") or rest.starts_with(">") then
      items.push(block_scalar(doc, strip_comment(rest), ind)?)
    elseif is_sequence_line(rest) or split_key(rest) != none then
      -- `- key: value` and `- - x`: the item starts on this line, further in
      let offset = ind + 1 + (after.len() - rest.len())
      doc.lines[doc.pos] = " ".repeat(offset) + rest
      items.push(parse_block(doc, offset)?)
    else
      items.push(inline_value(doc, rest)?)
      doc.pos += 1
    end
  end
  Ok(Json.array(items))
end

fun prepare(text: string) -> Result<array<string>, Error>
  let lines = text.replace("\r\n", "\n").split("\n")
  let n = 0
  for line in lines do
    n += 1
    let ind = indent_of(line)
    if ind < line.len() and line.substring(ind, ind + 1) == "\t" then
      return Err(Error { message: "line {n}: tabs cannot indent YAML" })
    end
  end
  Ok(lines)
end

--" Reads a YAML document (the first one) into a `Json` value. `err` says the line of what it cannot
read. An empty document is `null`. --"
fun parse(text: string) -> Result<Json, Error>
  let all = parse_all(text)?
  if all.is_empty() then
    return Ok(Json.null())
  end
  Ok(all[0])
end

--" Reads every document of a stream (`---` between them). --"
fun parse_all(text: string) -> Result<array<Json>, Error>
  let lines = prepare(text)?
  let docs: array<Json> = []
  let current: array<string> = []
  let started = false
  for line in lines do
    if line == "---" or line.starts_with("--- ") then
      if started or current.any(fun(l: string) -> bool not is_blank(l) end) then
        docs.push(parse_lines(current)?)
      end
      current = []
      started = true
      let after = line.substring(3, line.len()).trim()
      if after != "" and not after.starts_with("#") then
        current.push(after)
      end
      continue
    end
    if line == "..." then
      continue
    end
    current.push(line)
  end
  if started or current.any(fun(l: string) -> bool not is_blank(l) end) then
    docs.push(parse_lines(current)?)
  end
  Ok(docs)
end

fun parse_lines(lines: array<string>) -> Result<Json, Error>
  let doc = Doc { lines: lines, pos: 0 }
  let v = parse_block(doc, 0)?
  skip_blank(doc)
  if not at_end(doc) then
    return fail<Json>(doc, "unexpected text")
  end
  Ok(v)
end

-- ------------------------------------------------------------------------ writing

fun needs_quotes(s: string) -> bool
  if s == "" or s != s.trim() then
    return true
  end
  if not plain_scalar(s).is_string() then
    return true
  end
  if s == "yes" or s == "no" or s == "on" or s == "off" or s == "y" or s == "n" then
    return true
  end
  let first = s.substring(0, 1)
  if "-?:,[]\{\}#&*!|>'\"%@`".contains(first) then
    return true
  end
  s.contains(": ") or s.contains(" #") or s.contains("\n") or s.contains("\t") or s.ends_with(":")
end

fun quote(s: string) -> string
  let out = "\""
  for c in s.chars() do
    if c == "\"" then
      out += "\\\""
    elseif c == "\\" then
      out += "\\\\"
    elseif c == "\n" then
      out += "\\n"
    elseif c == "\t" then
      out += "\\t"
    elseif c == "\r" then
      out += "\\r"
    else
      out += c
    end
  end
  out + "\""
end

fun scalar_text(v: Json) -> string
  if v.is_null() then
    return "null"
  end
  if v.is_string() then
    let s = v.as_string()
    return if needs_quotes(s) then quote(s) else s end
  end
  v.to_text()
end

fun dump_into(v: Json, depth: int, out: array<string>)
  let pad = "  ".repeat(depth)
  if v.is_object() then
    let o = v.as_object()
    if o.is_empty() then
      out.push(pad + "\{\}")
      return
    end
    for k in o.keys() do
      let child = o[k] ?? Json.null()
      let key = if needs_quotes(k) then quote(k) else k end
      if child.is_object() and not child.as_object().is_empty() then
        out.push("{pad}{key}:")
        dump_into(child, depth + 1, out)
      elseif child.is_array() and not child.as_array().is_empty() then
        out.push("{pad}{key}:")
        dump_into(child, depth + 1, out)
      elseif child.is_object() then
        out.push("{pad}{key}: \{\}")
      elseif child.is_array() then
        out.push("{pad}{key}: []")
      else
        out.push("{pad}{key}: {scalar_text(child)}")
      end
    end
    return
  end
  if v.is_array() then
    let items = v.as_array()
    if items.is_empty() then
      out.push(pad + "[]")
      return
    end
    for item in items do
      if item.is_object() and not item.as_object().is_empty() then
        let inner: array<string> = []
        dump_into(item, depth + 1, inner)
        -- the first line of the mapping goes on the dash's line
        out.push(pad + "- " + inner[0].substring(pad.len() + 2, inner[0].len()))
        for i in 1..inner.len() do
          out.push(inner[i])
        end
      elseif item.is_array() and not item.as_array().is_empty() then
        let inner: array<string> = []
        dump_into(item, depth + 1, inner)
        out.push(pad + "- " + inner[0].substring(pad.len() + 2, inner[0].len()))
        for i in 1..inner.len() do
          out.push(inner[i])
        end
      elseif item.is_object() then
        out.push(pad + "- \{\}")
      elseif item.is_array() then
        out.push(pad + "- []")
      else
        out.push(pad + "- " + scalar_text(item))
      end
    end
    return
  end
  out.push(pad + scalar_text(v))
end

--" Writes a `Json` value as block-style YAML (two spaces per level), with the keys in their order.
Texts are quoted only when they would be read as something else. Multi-line texts are written in
double quotes with `\n`. --"
fun dump(v: Json) -> string
  let out: array<string> = []
  dump_into(v, 0, out)
  out.join("\n") + "\n"
end

export parse, parse_all, dump

--" A small text template engine, for mails, pages and reports.

```
import "@std/template.q" as template

let data = Json.parse("{\"name\": \"Ana\", \"items\": [\"a\", \"b\"]}").unwrap()
let text = template.render("Hello {{ name }}!{% for x in items %} [{{ x }}]{% end %}", data).unwrap()
-- Hello Ana! [a] [b]
```

The syntax:

- `{{ name }}`, `{{ user.name }}`, `{{ items.0 }}`: a value, found by the names of the keys (a number
  picks an element of an array). `{{ "text" }}` is a string of the template itself.
- `{{ name | upper }}`: filters `upper`, `lower`, `trim`, `capitalize`, `len`, `escape` (HTML) and
  `raw`, one after the other (`{{ name | trim | upper }}`).
- `{% if name %}...{% else %}...{% end %}` and `{% if not name %}...{% end %}`: a value is false
  when it is `null`, `false`, `0`, an empty string, an empty array or an empty object.
- `{% for x in items %}...{% end %}`: inside, `loop.index` (from 1), `loop.first` and `loop.last`.
- `{# a comment #}`.

A value that does not exist is an error when it is printed (`render`); `if` and `for` treat it as
false and empty. `render_html` escapes what `{{ }}` prints (`<`, `>`, `&`, `"`, `'`) unless the
filter `raw` is the last one.
--"

enum Node
    Text(text: string)
    Var(path: array<string>, literal: string?, filters: array<string>, line: int)
    If(path: array<string>, negate: bool, then_body: array<Node>, else_body: array<Node>, line: int)
    For(name: string, path: array<string>, body: array<Node>, line: int)
end

-- one piece of the template: its kind ("text", "var", "tag"), its text and its line
struct Token
    public kind: string
    public text: string
    public line: int
end

fun fail(message: string, line: int) -> Error
    Error { message: "template: {message} (line {line})" }
end

-- ------------------------------------------------------------------------- reading

fun tokenize(source: string) -> Result<array<Token>, Error>
    let tokens: array<Token> = []
    let chars = source.chars()
    let n = chars.len()
    let i = 0
    let line = 1
    let text = ""
    let text_line = 1
    let open = "\{"
    while i < n do
        let c = chars[i]
        let next = if i + 1 < n then chars[i + 1] else "" end
        if c == open and (next == open or next == "%" or next == "#") then
            if text != "" then
                tokens[] = Token { kind: "text", text: text, line: text_line }
                text = ""
            end
            let close = if next == open then "}" elseif next == "%" then "%" else "#" end
            let start_line = line
            let j = i + 2
            let found = false
            let inner = ""
            while j < n and not found do
                if chars[j] == close and j + 1 < n and chars[j + 1] == "}" then
                    found = true
                else
                    if chars[j] == "\n" then
                        line += 1
                    end
                    inner += chars[j]
                    j += 1
                end
            end
            if not found then
                return Err(fail("a tag is never closed", start_line))
            end
            if next == open then
                tokens[] = Token { kind: "var", text: inner.trim(), line: start_line }
            elseif next == "%" then
                tokens[] = Token { kind: "tag", text: inner.trim(), line: start_line }
            end
            i = j + 2
            text_line = line
        else
            if c == "\n" then
                line += 1
            end
            text += c
            i += 1
        end
    end
    if text != "" then
        tokens[] = Token { kind: "text", text: text, line: text_line }
    end
    Ok(tokens)
end

fun split_path(text: string) -> array<string>
    text.split(".")
end

-- `name | upper | trim` -> the name and the filters
fun split_filters(text: string) -> (string, array<string>)
    let parts = text.split("|")
    let filters: array<string> = []
    for i in 1..parts.len() do
        filters[] = parts[i].trim()
    end
    (parts[0].trim(), filters)
end

struct Parser
    public tokens: array<Token>
    public pos: int
end

impl Parser
    -- the nodes up to one of the `stops` tags (`else`, `end`) and which one ended them
    public fun block(self, stops: array<string>) -> Result<(array<Node>, string), Error>
        let nodes: array<Node> = []
        while self.pos < self.tokens.len() do
            let t = self.tokens[self.pos]
            self.pos += 1
            if t.kind == "text" then
                nodes[] = Node.Text(t.text)
            elseif t.kind == "var" then
                nodes[] = parse_var(t)?
            else
                let words = t.text.words()
                let head = if words.len() > 0 then words[0] else "" end
                if stops.contains(head) then
                    return Ok((nodes, head))
                end
                if head == "if" then
                    nodes[] = self.parse_if(t, words)?
                elseif head == "for" then
                    nodes[] = self.parse_for(t, words)?
                elseif head == "else" or head == "end" then
                    return Err(fail("`{head}` without a matching `if` or `for`", t.line))
                else
                    return Err(fail("unknown tag `{t.text}`", t.line))
                end
            end
        end
        Ok((nodes, ""))
    end

    fun parse_if(self, t: Token, words: array<string>) -> Result<Node, Error>
        let negate = words.len() == 3 and words[1] == "not"
        if words.len() != 2 and not negate then
            return Err(fail("write `if name` or `if not name`", t.line))
        end
        let path = split_path(words[words.len() - 1])
        let (then_body, ended) = self.block(["else", "end"])?
        let else_body: array<Node> = []
        if ended == "else" then
            let (more, ended_again) = self.block(["end"])?
            if ended_again != "end" then
                return Err(fail("this `if` has no `end`", t.line))
            end
            return Ok(Node.If(path, negate, then_body, more, t.line))
        end
        if ended != "end" then
            return Err(fail("this `if` has no `end`", t.line))
        end
        Ok(Node.If(path, negate, then_body, else_body, t.line))
    end

    fun parse_for(self, t: Token, words: array<string>) -> Result<Node, Error>
        if words.len() != 4 or words[2] != "in" then
            return Err(fail("write `for name in items`", t.line))
        end
        let (body, ended) = self.block(["end"])?
        if ended != "end" then
            return Err(fail("this `for` has no `end`", t.line))
        end
        Ok(Node.For(words[1], split_path(words[3]), body, t.line))
    end
end

fun parse_var(t: Token) -> Result<Node, Error>
    let (head, filters) = split_filters(t.text)
    if head == "" then
        return Err(fail("an empty value between braces", t.line))
    end
    for f in filters do
        if not ["upper", "lower", "trim", "capitalize", "len", "escape", "raw"].contains(f) then
            return Err(fail("unknown filter `{f}`", t.line))
        end
    end
    if head.starts_with("\"") then
        if head.len() < 2 or not head.ends_with("\"") then
            return Err(fail("a string needs a closing quote", t.line))
        end
        return Ok(Node.Var([], head.substring(1, head.len() - 1), filters, t.line))
    end
    Ok(Node.Var(split_path(head), none, filters, t.line))
end

fun parse(source: string) -> Result<array<Node>, Error>
    let tokens = tokenize(source)?
    let p = Parser { tokens: tokens, pos: 0 }
    let (nodes, ended) = p.block([])?
    Ok(nodes)
end

-- ----------------------------------------------------------------------- rendering

fun lookup(path: array<string>, root: Json, locals: map<string, Json>) -> Json?
    let current: Json? = locals[path[0]]
    if current == none then
        current = root.get(path[0])
    end
    for i in 1..path.len() do
        let value = current
        if value == none then
            return none
        end
        let seg = path[i]
        if value.is_object() then
            current = value.get(seg)
        elseif value.is_array() then
            let index = seg.to_int()
            current = if index == none then none else value.at(index) end
        else
            return none
        end
    end
    current
end

fun truthy(v: Json?) -> bool
    if v == none then
        return false
    end
    let j = v
    if j.is_null() then
        return false
    elseif j.is_bool() then
        return j.as_bool()
    elseif j.is_string() then
        return j.as_string() != ""
    elseif j.is_number() then
        return j.as_number() != 0.0
    elseif j.is_array() then
        return j.as_array().len() > 0
    end
    j.as_object().len() > 0
end

fun show(v: Json, line: int) -> Result<string, Error>
    if v.is_string() then
        return Ok(v.as_string())
    elseif v.is_number() then
        let x = v.as_number()
        if x == x.floor() as float and x.abs() < 1000000000000000.0 then
            return Ok("{x.floor()}")
        end
        return Ok("{x}")
    elseif v.is_bool() then
        return Ok(if v.as_bool() then "true" else "false" end)
    elseif v.is_null() then
        return Ok("")
    end
    Err(fail("an array or an object cannot be printed: pick one of its values", line))
end

fun html_escape(s: string) -> string
    s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")
end

fun apply_filter(name: string, s: string) -> string
    if name == "upper" then
        return s.upper()
    elseif name == "lower" then
        return s.lower()
    elseif name == "trim" then
        return s.trim()
    elseif name == "capitalize" then
        return s.capitalize()
    elseif name == "len" then
        return "{s.len()}"
    elseif name == "escape" then
        return html_escape(s)
    end
    s
end

struct Renderer
    public html: bool
    public out: array<string>
end

impl Renderer
    public fun nodes(self, nodes: array<Node>, root: Json, locals: map<string, Json>) -> Result<bool, Error>
        for node in nodes do
            match node
                case Text(text) then
                    self.out[] = text
                case Var(path, literal, filters, line) then
                    let text = ""
                    if literal != none then
                        text = literal
                    else
                        let found = lookup(path, root, locals)
                        if found == none then
                            let name_of = path.join(".")
                            return Err(fail("`{name_of}` is not defined", line))
                        end
                        text = show(found, line)?
                    end
                    let raw = filters.len() > 0 and filters[filters.len() - 1] == "raw"
                    for f in filters do
                        text = apply_filter(f, text)
                    end
                    if self.html and not raw and not filters.contains("escape") then
                        text = html_escape(text)
                    end
                    self.out[] = text
                case If(path, negate, then_body, else_body, line) then
                    let yes = truthy(lookup(path, root, locals))
                    if negate then
                        yes = not yes
                    end
                    if yes then
                        self.nodes(then_body, root, locals)?
                    else
                        self.nodes(else_body, root, locals)?
                    end
                case For(name, path, body, line) then
                    let found = lookup(path, root, locals)
                    if found != none then
                        let items = found
                        if items.is_array() then
                            let list = items.as_array()
                            for i, item in list do
                                let loop_info: map<string, Json> = {
                                    "index": Json.number((i + 1) as float),
                                    "first": Json.boolean(i == 0),
                                    "last": Json.boolean(i == list.len() - 1)
                                }
                                let inner = locals.merge({ name: item, "loop": Json.object(loop_info) })
                                self.nodes(body, root, inner)?
                            end
                        elseif not items.is_null() then
                            let name_of = path.join(".")
                            return Err(fail("`{name_of}` is not a list", line))
                        end
                    end
            end
        end
        Ok(true)
    end
end

fun render_with(source: string, data: Json, html: bool) -> Result<string, Error>
    let nodes = parse(source)?
    let r = Renderer { html: html, out: [] }
    let locals: map<string, Json> = {}
    r.nodes(nodes, data, locals)?
    Ok(r.out.join(""))
end

--" Fills the template with `data` (a `Json` object). `err` if the template is wrong, or prints a
value that does not exist. --"
fun render(source: string, data: Json) -> Result<string, Error>
    render_with(source, data, false)
end

--" Like `render`, for HTML: what `{{ }}` prints is escaped, unless its last filter is `raw`. --"
fun render_html(source: string, data: Json) -> Result<string, Error>
    render_with(source, data, true)
end

--" Like `render`, for plain texts only: `values` maps names to strings. --"
fun render_text(source: string, values: map<string, string>) -> Result<string, Error>
    let fields: map<string, Json> = {}
    for k, v in values do
        fields[k] = Json.string(v)
    end
    render(source, Json.object(fields))
end

export render, render_html, render_text

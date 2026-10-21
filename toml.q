--" TOML, read into a `Json` value (an object): tables `[a.b]`, arrays of tables `[[a]]`, dotted
keys, strings (basic, literal, and the multi-line forms), integers (decimal, `0x`, `0o`, `0b`, with
`_`), floats (including `inf` and `nan`), booleans, arrays, inline tables, and dates, which stay
text. Numbers are read as floats, so an integer beyond 2^53 loses its last digits.

```
import "@std/toml.q" as toml

let config = toml.parse("[server]\nport = 8080\nhosts = [\"a\", \"b\"]\n").unwrap()
let port = config.get("server").unwrap().get("port").unwrap().as_number()   -- 8080.0
```
--"

struct Reader
    public chars: array<string>
    public pos: int
    public line: int
end

impl Reader
    public fun more(self) -> bool
        self.pos < self.chars.len()
    end

    public fun peek(self) -> string
        if self.pos < self.chars.len() then
            self.chars[self.pos]
        else
            ""
        end
    end

    public fun peek_at(self, offset: int) -> string
        let i = self.pos + offset
        if i < self.chars.len() then
            self.chars[i]
        else
            ""
        end
    end

    public fun next(self) -> string
        let c = self.peek()
        self.pos += 1
        if c == "\n" then
            self.line += 1
        end
        c
    end

    public fun fail(self, message: string) -> Error
        Error { message: "toml: {message} (line {self.line})" }
    end

    -- spaces and tabs
    public fun skip_blanks(self)
        while self.peek() == " " or self.peek() == "\t" do
            self.pos += 1
        end
    end

    -- blanks, comments and new lines: whatever may separate two items
    public fun skip_space(self)
        let going = true
        while going do
            let c = self.peek()
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                self.next()
            elseif c == "#" then
                while self.more() and self.peek() != "\n" do
                    self.pos += 1
                end
            else
                going = false
            end
        end
    end

    -- the end of a line: blanks, then maybe a comment, then a new line (or the end)
    public fun end_of_line(self) -> Result<bool, Error>
        self.skip_blanks()
        if self.peek() == "#" then
            while self.more() and self.peek() != "\n" do
                self.pos += 1
            end
        end
        if self.peek() == "\r" then
            self.pos += 1
        end
        if self.more() and self.peek() != "\n" then
            return Err(self.fail("unexpected `{self.peek()}` after the value"))
        end
        if self.more() then
            self.next()
        end
        Ok(true)
    end
end

fun is_bare(c: string) -> bool
    c != "" and (c.is_alpha() or c.is_digit() or c == "_" or c == "-")
end

-- ------------------------------------------------------------------------ strings

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

fun escape_char(r: Reader) -> Result<string, Error>
    let c = r.next()
    if c == "n" then
        return Ok("\n")
    elseif c == "t" then
        return Ok("\t")
    elseif c == "r" then
        return Ok("\r")
    elseif c == "b" then
        return Ok(8.char())
    elseif c == "f" then
        return Ok(12.char())
    elseif c == "\"" then
        return Ok("\"")
    elseif c == "\\" then
        return Ok("\\")
    elseif c == "u" or c == "U" then
        let size = if c == "u" then 4 else 8 end
        let digits = ""
        for i in 0..size do
            digits += r.next()
        end
        let code = hex_value(digits)
        if code == none or code > 1114111 then
            return Err(r.fail("`\\{c}{digits}` is not a character"))
        end
        return Ok(code.char())
    end
    Err(r.fail("unknown escape `\\{c}`"))
end

fun basic_string(r: Reader) -> Result<string, Error>
    r.next()
    let multi = r.peek() == "\"" and r.peek_at(1) == "\""
    if multi then
        r.next()
        r.next()
        if r.peek() == "\n" then
            r.next()
        end
    end
    let out = ""
    while true do
        if not r.more() then
            return Err(r.fail("a string is never closed"))
        end
        let c = r.next()
        if c == "\"" then
            if not multi then
                return Ok(out)
            end
            if r.peek() == "\"" and r.peek_at(1) == "\"" then
                r.next()
                r.next()
                return Ok(out)
            end
            out += c
        elseif c == "\\" then
            if multi and (r.peek() == "\n" or r.peek() == " " or r.peek() == "\r") then
                -- a backslash at the end of a line removes the new line and the blanks after it
                while r.peek() == " " or r.peek() == "\t" or r.peek() == "\n" or r.peek() == "\r" do
                    r.next()
                end
            else
                out += escape_char(r)?
            end
        elseif c == "\n" and not multi then
            return Err(r.fail("a string cannot hold a new line (use \"\"\" for several lines)"))
        else
            out += c
        end
    end
    Ok(out)
end

fun literal_string(r: Reader) -> Result<string, Error>
    r.next()
    let multi = r.peek() == "'" and r.peek_at(1) == "'"
    if multi then
        r.next()
        r.next()
        if r.peek() == "\n" then
            r.next()
        end
    end
    let out = ""
    while true do
        if not r.more() then
            return Err(r.fail("a string is never closed"))
        end
        let c = r.next()
        if c == "'" then
            if not multi then
                return Ok(out)
            end
            if r.peek() == "'" and r.peek_at(1) == "'" then
                r.next()
                r.next()
                return Ok(out)
            end
        elseif c == "\n" and not multi then
            return Err(r.fail("a string cannot hold a new line (use ''' for several lines)"))
        end
        out += c
    end
    Ok(out)
end

-- ----------------------------------------------------------------------------- keys

-- `a.b."c d"` -> ["a", "b", "c d"]
fun key_path(r: Reader) -> Result<array<string>, Error>
    let parts: array<string> = []
    while true do
        r.skip_blanks()
        let c = r.peek()
        if c == "\"" then
            parts[] = basic_string(r)?
        elseif c == "'" then
            parts[] = literal_string(r)?
        elseif is_bare(c) then
            let name = ""
            while is_bare(r.peek()) do
                name += r.next()
            end
            parts[] = name
        else
            return Err(r.fail("a key was expected"))
        end
        r.skip_blanks()
        if r.peek() == "." then
            r.next()
        else
            return Ok(parts)
        end
    end
    Ok(parts)
end

-- ---------------------------------------------------------------------------- values

fun scalar(r: Reader) -> Result<Json, Error>
    let text = ""
    while r.more() and r.peek() != "," and r.peek() != "]" and r.peek() != "}" and r.peek() != "#" and r.peek() != "\n" and r.peek() != "\r" and r.peek() != " " and r.peek() != "\t" do
        text += r.next()
    end
    if text == "" then
        return Err(r.fail("a value was expected"))
    end
    if text == "true" then
        return Ok(Json.boolean(true))
    elseif text == "false" then
        return Ok(Json.boolean(false))
    end
    -- a date and a time written with a space between them
    if text.len() == 10 and text.substring(4, 5) == "-" and r.peek() == " " and r.peek_at(1).is_digit() then
        r.next()
        while r.more() and r.peek() != "," and r.peek() != "]" and r.peek() != "}" and r.peek() != "#" and r.peek() != "\n" and r.peek() != "\r" and r.peek() != " " do
            text += (if text.len() == 10 then " " else "" end) + r.next()
        end
    end
    if text.len() >= 10 and text.substring(4, 5) == "-" and text.substring(7, 8) == "-" then
        return Ok(Json.string(text))
    end
    if text.len() >= 8 and text.substring(2, 3) == ":" and text.substring(5, 6) == ":" then
        return Ok(Json.string(text))
    end
    let clean = text.replace("_", "")
    if clean == "inf" or clean == "+inf" then
        return Ok(Json.number(float.INFINITY))
    elseif clean == "-inf" then
        return Ok(Json.number(-float.INFINITY))
    elseif clean == "nan" or clean == "+nan" or clean == "-nan" then
        return Ok(Json.number(float.NAN))
    end
    let sign = 1.0
    let digits = clean
    if clean.starts_with("+") then
        digits = clean.substring(1, clean.len())
    elseif clean.starts_with("-") then
        sign = -1.0
        digits = clean.substring(1, clean.len())
    end
    for prefix_base in [("0x", 16), ("0o", 8), ("0b", 2)] do
        let (prefix, base) = prefix_base
        if digits.starts_with(prefix) then
            let n = 0.0
            for c in digits.substring(2, digits.len()).chars() do
                let d = "0123456789abcdef".index_of(c.lower())
                if d == none or d >= base then
                    return Err(r.fail("`{text}` is not a number"))
                end
                n = n * (base as float) + (d as float)
            end
            return Ok(Json.number(n))
        end
    end
    let number = digits.to_float()
    if number == none or not digits.substring(0, 1).is_digit() then
        return Err(r.fail("`{text}` is not a value"))
    end
    Ok(Json.number(sign * number))
end

fun value(r: Reader) -> Result<Json, Error>
    let c = r.peek()
    if c == "\"" then
        return Ok(Json.string(basic_string(r)?))
    elseif c == "'" then
        return Ok(Json.string(literal_string(r)?))
    elseif c == "[" then
        return array_value(r)
    elseif c == "\{" then
        return inline_table(r)
    end
    scalar(r)
end

fun array_value(r: Reader) -> Result<Json, Error>
    r.next()
    let items: array<Json> = []
    while true do
        r.skip_space()
        if r.peek() == "]" then
            r.next()
            return Ok(Json.array(items))
        end
        if not r.more() then
            return Err(r.fail("an array is never closed"))
        end
        items[] = value(r)?
        r.skip_space()
        if not r.more() then
            return Err(r.fail("an array is never closed"))
        end
        if r.peek() == "," then
            r.next()
        elseif r.peek() != "]" then
            return Err(r.fail("`,` or `]` was expected in the array"))
        end
    end
    Ok(Json.array(items))
end

fun inline_table(r: Reader) -> Result<Json, Error>
    r.next()
    let table: map<string, Json> = {}
    r.skip_blanks()
    if r.peek() == "}" then
        r.next()
        return Ok(Json.object(table))
    end
    while true do
        r.skip_blanks()
        let path = key_path(r)?
        r.skip_blanks()
        if r.peek() != "=" then
            return Err(r.fail("`=` was expected after the key"))
        end
        r.next()
        r.skip_blanks()
        set_path(table, path, value(r)?, r)?
        r.skip_blanks()
        if r.peek() == "," then
            r.next()
        elseif r.peek() == "}" then
            r.next()
            return Ok(Json.object(table))
        else
            return Err(r.fail("`,` or `}` was expected in the inline table"))
        end
    end
    Ok(Json.object(table))
end

-- ---------------------------------------------------------------------------- tables

-- the table at `path` in `table`, made when it is missing (the last table of an array of tables)
fun table_at(table: map<string, Json>, path: array<string>, r: Reader) -> Result<map<string, Json>, Error>
    let current = table
    for key in path do
        let found = current[key]
        if found == none then
            let made: map<string, Json> = {}
            current[key] = Json.object(made)
            current = made
        else
            let j = found
            if j.is_object() then
                current = j.as_object()
            elseif j.is_array() and j.as_array().len() > 0 and j.as_array()[j.as_array().len() - 1].is_object() then
                let list = j.as_array()
                current = list[list.len() - 1].as_object()
            else
                return Err(r.fail("`{key}` is not a table"))
            end
        end
    end
    Ok(current)
end

fun set_path(table: map<string, Json>, path: array<string>, v: Json, r: Reader) -> Result<bool, Error>
    let parent = table_at(table, path.take(path.len() - 1), r)?
    let last = path[path.len() - 1]
    if parent.has(last) then
        return Err(r.fail("`{last}` is defined twice"))
    end
    parent[last] = v
    Ok(true)
end

--" Reads TOML text into a `Json` object. `err`, with the line, when the text is not valid TOML
(or uses something this reader does not do: the dates stay text, and the keys are not checked for
all the fine points of the format). --"
fun parse(text: string) -> Result<Json, Error>
    let r = Reader { chars: text.chars(), pos: 0, line: 1 }
    let root: map<string, Json> = {}
    let current = root
    while true do
        r.skip_space()
        if not r.more() then
            break
        end
        if r.peek() == "[" then
            r.next()
            let array_of_tables = r.peek() == "["
            if array_of_tables then
                r.next()
            end
            let path = key_path(r)?
            r.skip_blanks()
            if r.peek() != "]" then
                return Err(r.fail("`]` was expected after the name of the table"))
            end
            r.next()
            if array_of_tables then
                if r.peek() != "]" then
                    return Err(r.fail("`]]` was expected after the name of an array of tables"))
                end
                r.next()
            end
            r.end_of_line()?
            if array_of_tables then
                let parent = table_at(root, path.take(path.len() - 1), r)?
                let name = path[path.len() - 1]
                let fresh: map<string, Json> = {}
                let existing = parent[name]
                if existing == none then
                    parent[name] = Json.array([Json.object(fresh)])
                else
                    let list = existing
                    if not list.is_array() then
                        return Err(r.fail("`{name}` is not an array of tables"))
                    end
                    list.as_array()[] = Json.object(fresh)
                end
                current = fresh
            else
                current = table_at(root, path, r)?
            end
        else
            let path = key_path(r)?
            r.skip_blanks()
            if r.peek() != "=" then
                return Err(r.fail("`=` was expected after the key"))
            end
            r.next()
            r.skip_blanks()
            set_path(current, path, value(r)?, r)?
            r.end_of_line()?
        end
    end
    Ok(Json.object(root))
end

export parse

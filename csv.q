--" CSV, as RFC 4180 describes it: fields separated by a comma (or another character), a
field may be quoted with `"` to hold the separator, new lines and quotes (a quote inside is
written twice), and lines end with `\n` or `\r\n`.

```
import "@std/csv.q" as csv

let rows = csv.parse("name,age\nana,31\n\"bob, jr\",27\n").unwrap()
-- [["name", "age"], ["ana", "31"], ["bob, jr", "27"]]
```
--"

--" Reads CSV text separated by commas: one array of fields for each line. An empty line is a
line with one empty field; a final new line does not make an extra line. `err` when a quoted
field is never closed. --"
fun parse(text: string) -> Result<array<array<string>>, Error>
  parse_with(text, ",")
end

--" Like `parse`, with another separator: one character, such as `";"` or `"\t"`. --"
fun parse_with(text: string, delimiter: string) -> Result<array<array<string>>, Error>
  if delimiter.len() != 1 or delimiter == "\"" or delimiter == "\n" or delimiter == "\r" then
    return Err(Error { message: "csv: the separator must be one character, other than a quote or a new line" })
  end
  let rows: array<array<string>> = []
  let row: array<string> = []
  let field = ""
  let chars = text.chars()
  let n = chars.len()
  let i = 0
  let in_quotes = false
  let quoted = false
  let line = 1
  let quote_line = 0
  while i < n do
    let c = chars[i]
    if in_quotes then
      if c == "\"" then
        if i + 1 < n and chars[i + 1] == "\"" then
          field += "\""
          i += 1
        else
          in_quotes = false
        end
      else
        if c == "\n" then
          line += 1
        end
        field += c
      end
    elseif c == "\"" and field == "" and not quoted then
      in_quotes = true
      quoted = true
      quote_line = line
    elseif c == delimiter then
      row[] = field
      field = ""
      quoted = false
    elseif c == "\r" and i + 1 < n and chars[i + 1] == "\n" then
      -- the "\n" that follows ends the line
      field += ""
    elseif c == "\n" or c == "\r" then
      row[] = field
      rows[] = row
      row = []
      field = ""
      quoted = false
      line += 1
    else
      field += c
    end
    i += 1
  end
  if in_quotes then
    return Err(Error { message: "csv: the quoted field that starts on line {quote_line} is never closed" })
  end
  if field != "" or quoted or row.len() > 0 then
    row[] = field
    rows[] = row
  end
  Ok(rows)
end

--" Reads CSV text whose first line names the columns: one map for each following line, from
the name of a column to the field. A line with fewer fields than the header has empty strings
for the missing ones; extra fields are dropped. --"
fun parse_records(text: string) -> Result<array<map<string, string>>, Error>
  let rows = parse(text)?
  to_records(rows)
end

--" The same as `parse_records` for rows already read. --"
fun to_records(rows: array<array<string>>) -> Result<array<map<string, string>>, Error>
  let records: array<map<string, string>> = []
  if rows.len() == 0 then
    return Ok(records)
  end
  let header = rows[0]
  for r in 1..rows.len() do
    let record: map<string, string> = {}
    for i, name in header do
      record[name] = if i < rows[r].len() then rows[r][i] else "" end
    end
    records[] = record
  end
  Ok(records)
end

--" CSV text for these rows, separated by commas, each line ending with `\n`. A field is
quoted only when it has to be (it holds the separator, a quote, or a new line). --"
fun to_text(rows: array<array<string>>) -> string
  to_text_with(rows, ",")
end

--" Like `to_text`, with another one-character separator. --"
fun to_text_with(rows: array<array<string>>, delimiter: string) -> string
  let lines: array<string> = []
  for row in rows do
    let fields: array<string> = []
    for f in row do
      fields[] = quote_if_needed(f, delimiter)
    end
    lines[] = fields.join(delimiter)
  end
  if lines.len() == 0 then
    return ""
  end
  lines.join("\n") + "\n"
end

fun quote_if_needed(field: string, delimiter: string) -> string
  if field.contains(delimiter) or field.contains("\"") or field.contains("\n") or field.contains("\r") then
    return "\"" + field.replace("\"", "\"\"") + "\""
  end
  field
end

export parse, parse_with, parse_records, to_records, to_text, to_text_with

# csv.q

## `fun parse(text: string) -> Result<array<array<string>>, Error>`

Reads CSV text separated by commas: one array of fields for each line. An empty line is a
line with one empty field; a final new line does not make an extra line. `err` when a quoted
field is never closed.

## `fun parse_with(text: string, delimiter: string) -> Result<array<array<string>>, Error>`

Like `parse`, with another separator: one character, such as `";"` or `"\t"`.

## `fun parse_records(text: string) -> Result<array<map<string, string>>, Error>`

Reads CSV text whose first line names the columns: one map for each following line, from
the name of a column to the field. A line with fewer fields than the header has empty strings
for the missing ones; extra fields are dropped.

## `fun to_records(rows: array<array<string>>) -> Result<array<map<string, string>>, Error>`

The same as `parse_records` for rows already read.

## `fun to_text(rows: array<array<string>>) -> string`

CSV text for these rows, separated by commas, each line ending with `\n`. A field is
quoted only when it has to be (it holds the separator, a quote, or a new line).

## `fun to_text_with(rows: array<array<string>>, delimiter: string) -> string`

Like `to_text`, with another one-character separator.

# template.q

## `fun render(source: string, data: Json) -> Result<string, Error>`

Fills the template with `data` (a `Json` object). `err` if the template is wrong, or prints a
value that does not exist.

## `fun render_html(source: string, data: Json) -> Result<string, Error>`

Like `render`, for HTML: what `{{ }}` prints is escaped, unless its last filter is `raw`.

## `fun render_text(source: string, values: map<string, string>) -> Result<string, Error>`

Like `render`, for plain texts only: `values` maps names to strings.

# toml.q

## `fun parse(text: string) -> Result<Json, Error>`

Reads TOML text into a `Json` object. `err`, with the line, when the text is not valid TOML
(or uses something this reader does not do: the dates stay text, and the keys are not checked for
all the fine points of the format).


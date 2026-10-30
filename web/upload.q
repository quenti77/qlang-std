--" # File uploads

What an HTML form with `enctype="multipart/form-data"` sends: text fields and files. `receive` reads
them, checks the files against your rules and gives the fields and the files; `Upload.save` writes a
file in a folder under a name the server chooses.

```
#[web.Post("/avatar")]
fun avatar(req: Request) -> Result<string, web.Problem>
  let rules = Rules { max_size: 2097152, types: ["image/png", "image/jpeg"], required: true }
  let sent = receive(req, rules)
  if sent.is_err() then
    return Result<string, web.Problem>.Err(sent.unwrap_err())
  end
  let file = sent.unwrap().files[0]
  let saved = file.save("storage/avatars")      -- "storage/avatars/Qk3x....png"
  ...
end
```

Rules the server applies, whatever the browser says:

- **Size**: `max_size` bytes for each file (`413`), `max_files` files at most (`413`). The request itself
  is bounded by `qlang serve --max-body` (1 MB unless you raise it: `--max-body 20m`).
- **Type**: `types` lists the content types allowed. The type is read from the **content** of the file
  (a PNG, JPEG, GIF, WebP, PDF, ZIP or gzip file is recognised by its first bytes), not from the
  `Content-Type` the browser announced, which anyone can change; a file whose content is not
  recognised is accepted as text only when its content is valid text and `text/plain` (or the type it
  announced, for `text/csv`, `application/json`...) is allowed (`415` otherwise).
- **Name**: `save` never uses the name the browser sent (`../../etc/passwd`): the file is called
  after a random token, with an extension taken from the recognised type (or the letters and digits of
  the original extension).
--"
import "app.q" as web

--" What `receive` accepts. --"
struct Rules
  --" The largest file, in bytes (5 MB). --"
  public max_size: int = 5242880
  --" The most files in one request. --"
  public max_files: int = 10
  --" The content types allowed (`["image/png", "image/jpeg"]`); empty: any. --"
  public types: array<string> = []
  --" Refuse a request without any file (`422`). --"
  public required: bool = false
end

--" A file of the form. --"
struct Upload
  --" The name of the form field it came in. --"
  public field: string
  --" The name the browser gave it (do not trust it, do not use it as a path). --"
  public filename: string
  --" The type found in its content, or the one the browser announced. --"
  public content_type: string
  public size: int
  public data: bytes
end

--" The text fields and the files of a form. --"
struct Submission
  public fields: map<string, string>
  public files: array<Upload>
end

-- (type, first bytes in hexadecimal, extension)
fun signatures() -> array<array<string>>
  [
    ["image/png", "89504e470d0a1a0a", "png"],
    ["image/jpeg", "ffd8ff", "jpg"],
    ["image/gif", "474946383761", "gif"],
    ["image/gif", "474946383961", "gif"],
    ["application/pdf", "255044462d", "pdf"],
    ["application/zip", "504b0304", "zip"],
    ["application/gzip", "1f8b", "gz"],
  ]
end

--" The content type of `data` read from its first bytes, or `none` when it is not one of the known
formats (PNG, JPEG, GIF, WebP, PDF, ZIP, gzip). --"
fun sniff(data: bytes) -> string?
  let head = data.slice(0, 16).hex()
  for s in signatures() do
    if head.starts_with(s[1]) then
      return s[0]
    end
  end
  if head.len() >= 24 and head.starts_with("52494646") and head.substring(16, 24) == "57454250" then
    return "image/webp"
  end
  none
end

fun extension_of_type(kind: string) -> string?
  for s in signatures() do
    if s[0] == kind then
      return s[2]
    end
  end
  if kind == "image/webp" then
    return "webp"
  end
  none
end

fun safe_extension(filename: string) -> string
  let dot = filename.last_index_of(".")
  if dot == none then
    return ""
  end
  let tail = filename.substring(dot + 1, filename.len()).lower()
  let clean = tail.chars().filter(fun(c: string) -> bool c.is_alpha() or c.is_digit() end).join("")
  if clean.len() == 0 or clean.len() > 8 then "" else clean end
end

impl Upload
  --" The extension for the file name on disk, without the dot: from the recognised type, else the
  letters and digits of the original extension, else empty. --"
  public fun extension(self) -> string
    let known = extension_of_type(self.content_type)
    if known != none then
      return known
    end
    safe_extension(self.filename)
  end

  --" Writes the file in `dir` (made if missing) under a random name and gives its path. --"
  public fun save(self, dir: string) -> Result<string, Error>
    let made = fs.create_dir(dir)
    if made.is_err() then
      return Result<string, Error>.Err(made.unwrap_err())
    end
    let token = Crypto.token(16)
    if token.is_err() then
      return Result<string, Error>.Err(token.unwrap_err())
    end
    let ext = self.extension()
    let name = if ext == "" then token.unwrap() else token.unwrap() + "." + ext end
    let path = if dir.ends_with("/") then dir + name else dir + "/" + name end
    let written = fs.write_bytes(path, self.data)
    if written.is_err() then
      return Result<string, Error>.Err(written.unwrap_err())
    end
    Result<string, Error>.Ok(path)
  end
end

fun refuse<T>(status: int, message: string) -> Result<T, web.Problem>
  Result<T, web.Problem>.Err(web.Problem { status: status, message: message })
end

fun allowed(rules: Rules, found: string?, announced: string?, data: bytes) -> string?
  if found != none then
    if rules.types.is_empty() or rules.types.contains(found) then
      return found
    end
    return none
  end
  -- not a known binary format: plain text may pass with the type the browser announced
  let text = data.to_string()
  let said = (announced ?? "text/plain").split(";")[0].trim().lower()
  if text == none or data.slice(0, 8192).hex().contains("00") then
    return if rules.types.is_empty() then said else none end
  end
  if rules.types.is_empty() or rules.types.contains(said) then
    return said
  end
  none
end

--" Reads the multipart body of a request. The `Err` is a `Problem` (a handler can return it as it
is): `400` for a body that is not multipart, `413` for a file or a count over the rules, `415` for a
type that is not allowed, `422` when a file is `required` and there is none. --"
fun receive(req: Request, rules: Rules) -> Result<Submission, web.Problem>
  let parts = req.multipart()
  if parts.is_err() then
    return refuse<Submission>(400, parts.unwrap_err().message)
  end
  let fields: map<string, string> = {}
  let files: array<Upload> = []
  for part in parts.unwrap() do
    let name = part.filename
    if name == none then
      fields[part.name] = part.text() ?? ""
      continue
    end
    if name == "" and part.data.is_empty() then
      continue
    end
    if part.data.len() > rules.max_size then
      return refuse<Submission>(413, "{part.name}: the file is larger than {rules.max_size} bytes")
    end
    let kind = allowed(rules, sniff(part.data), part.content_type, part.data)
    if kind == none then
      return refuse<Submission>(415, "{part.name}: this type of file is not allowed")
    end
    files.push(Upload { field: part.name, filename: name, content_type: kind, size: part.data.len(), data: part.data })
    if files.len() > rules.max_files then
      return refuse<Submission>(413, "at most {rules.max_files} files")
    end
  end
  if rules.required and files.is_empty() then
    return refuse<Submission>(422, "a file is required")
  end
  Result<Submission, web.Problem>.Ok(Submission { fields: fields, files: files })
end

export Rules, Upload, Submission, receive, sniff

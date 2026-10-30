import "app.q" as web
import "testing.q" as testing
import "upload.q" as up

#[web.Post("/upload")]
fun upload(req: Request) -> Result<string, web.Problem>
  let rules = up.Rules { max_size: 64, max_files: 2, types: ["image/png", "text/plain"], required: true }
  let sent = up.receive(req, rules)
  if sent.is_err() then
    return Result<string, web.Problem>.Err(sent.unwrap_err())
  end
  let form = sent.unwrap()
  let names = form.files.map(fun(f: up.Upload) -> string "{f.field}:{f.content_type}:{f.size}" end)
  Result<string, web.Problem>.Ok("{form.fields["title"] ?? "-"} {names.join(",")}")
end

fun raw(items: array<int>) -> bytes
  bytes.from_array(items) ?? "".to_bytes()
end

fun app() -> web.App
  let a = web.App.new([])
  a.controllers(Reflect.callables())
  a
end

fun png_file() -> testing.TestFile
  testing.TestFile { field: "avatar", filename: "me.PNG", content_type: "image/png", data: raw([137, 80, 78, 71, 13, 10, 26, 10, 0, 0]) }
end

fun test_fields_and_a_png_are_read()
  let client = testing.Client.new(app())
  let r = client.post_multipart("/upload", {"title": "Hi"}, [png_file()])
  r.expect_status(200)
  assert_eq(r.body, "Hi avatar:image/png:10")
end

fun test_the_type_comes_from_the_content_not_from_the_announced_type()
  let client = testing.Client.new(app())
  let fake = testing.TestFile { field: "avatar", filename: "x.png", content_type: "image/png", data: raw([255, 216, 255, 224, 0, 16, 74, 70]) }
  -- a JPEG announced as a PNG: the JPEG is not in the allowed list
  client.post_multipart("/upload", {}, [fake]).expect_status(415)
  let text = testing.TestFile { field: "note", filename: "a.txt", content_type: "text/plain", data: "hello".to_bytes() }
  assert_eq(client.post_multipart("/upload", {}, [text]).body, "- note:text/plain:5")
end

fun test_the_rules_refuse_what_is_too_big_too_many_or_missing()
  let client = testing.Client.new(app())
  let big = testing.TestFile { field: "note", filename: "a.txt", content_type: "text/plain", data: ("x".repeat(65)).to_bytes() }
  client.post_multipart("/upload", {}, [big]).expect_status(413)
  client.post_multipart("/upload", {}, [png_file(), png_file(), png_file()]).expect_status(413)
  client.post_multipart("/upload", {"title": "only text"}, []).expect_status(422)
  client.post("/upload", "not multipart").expect_status(400)
end

fun test_a_binary_file_that_is_not_recognised_is_refused()
  let client = testing.Client.new(app())
  let odd = testing.TestFile { field: "f", filename: "a.bin", content_type: "text/plain", data: raw([0, 1, 2, 3, 255]) }
  client.post_multipart("/upload", {}, [odd]).expect_status(415)
end

fun test_save_writes_under_a_random_name_and_ignores_the_given_one()
  let dir = "/tmp/qlang-upload-test-{Crypto.token(6).unwrap()}"
  let file = up.Upload { field: "a", filename: "../../etc/passwd.PNG", content_type: "image/png", size: 3, data: "abc".to_bytes() }
  let path = file.save(dir).unwrap()
  assert(path.starts_with(dir + "/"))
  assert(path.ends_with(".png"))
  assert(not path.contains(".."))
  assert_eq(fs.read(path).unwrap(), "abc")
  let other = up.Upload { field: "a", filename: "notes.TXT", content_type: "application/octet-stream", size: 1, data: "z".to_bytes() }
  assert(other.save(dir).unwrap().ends_with(".txt"))
  let nameless = up.Upload { field: "a", filename: "weird", content_type: "application/octet-stream", size: 1, data: "z".to_bytes() }
  assert(not nameless.save(dir).unwrap().contains("."))
end

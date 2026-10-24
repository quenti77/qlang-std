-- Routes for the recipes of the guide, checked by `recipes_test.q`.
import "app.q" as web

#[web.Get("/old")]
fun old() -> Response
  Response.redirect("/new")
end

#[web.Get("/page")]
fun page() -> Response
  Response.html("<h1>Hello</h1>")
end

#[web.Get("/file")]
fun file() -> Response
  let res = Response.text("a,b\n1,2")
  res.headers["Content-Type"] = "text/csv"
  res.headers["Content-Disposition"] = "attachment; filename=\"data.csv\""
  res.with_cookie(Cookie { name: "seen", value: "1", max_age: 60 })
end

#[web.Post("/upload")]
fun upload(req: Request) -> Result<string, HttpError>
  let parts = req.multipart()
  if parts.is_err() then
    return Result<string, HttpError>.Err(HttpError { status: 400, message: "not a multipart form" })
  end
  let names: array<string> = []
  for p in parts.unwrap() do
    names.push("{p.name}:{p.filename ?? "-"}:{p.data.len()}")
  end
  Result<string, HttpError>.Ok(names.join(","))
end

#[web.Get("/boom")]
fun boom() -> Result<string, Error>
  Result<string, Error>.Err(Error { message: "db down" })
end

#[web.Get("/ping")]
fun ping() -> string
  "pong"
end

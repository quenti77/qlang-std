--" # Testing an application without a server

A `Client` sends requests straight to `App.handle`: no port, no socket, the same code path as a
real request (middleware, injection, validation). It remembers the cookies of the responses and
sends them back, so a login and what follows can be tested as one visit.

```
let client = Client.new(app)
let r = client.get("/posts/1")
r.expect_status(200)
let post = r.json<Post>().unwrap()

client.bearer("token")
client.post_json("/posts", NewPost { title: "Hello" }).expect_status(201)
```
--"
import "app.q" as web

--" What the application answered. --"
struct Reply
  public status: int
  public headers: map<string, string>
  public body: string
  public cookies: array<Cookie>
end

impl Reply
  --" The body read as a `T`. --"
  public fun json<T>(self) -> Result<T, Error>
    let parsed = Json.parse(self.body)
    if parsed.is_err() then
      return Result<T, Error>.Err(parsed.unwrap_err())
    end
    Json.to<T>(parsed.unwrap())
  end

  --" The value of a header (the name is compared in lower case), or `none`. --"
  public fun header(self, name: string) -> string?
    let wanted = name.lower()
    for key in self.headers.keys() do
      if key.lower() == wanted then
        return self.headers[key]
      end
    end
    none
  end

  --" Fails the test, with the body, unless the status is `code`. Gives the reply back. --"
  public fun expect_status(self, code: int) -> Reply
    if self.status != code then
      panic("expected status {code}, got {self.status}: {self.body}")
    end
    self
  end

  --" Fails the test unless the body contains `text`. Gives the reply back. --"
  public fun expect_body_contains(self, text: string) -> Reply
    if not self.body.contains(text) then
      panic("the body does not contain {text}: {self.body}")
    end
    self
  end
end

--" Sends requests to an application. --"
struct Client
  app: web.App
  public headers: map<string, string>
  public cookies: map<string, string>
end

impl Client
  public fun new(app: web.App) -> Client
    Client { app: app, headers: {}, cookies: {} }
  end

  --" A header sent with every request from now on. --"
  public fun header(self, name: string, value: string)
    self.headers[name.lower()] = value
  end

  --" Sends `Authorization: Bearer token` with every request from now on. --"
  public fun bearer(self, token: string)
    self.header("authorization", "Bearer {token}")
  end

  --" Forgets the cookies. --"
  public fun forget_cookies(self)
    self.cookies = {}
  end

  public fun get(self, path: string) -> Reply
    self.send("GET", path, none)
  end

  public fun delete(self, path: string) -> Reply
    self.send("DELETE", path, none)
  end

  public fun post(self, path: string, body: string) -> Reply
    self.send("POST", path, body)
  end

  public fun put(self, path: string, body: string) -> Reply
    self.send("PUT", path, body)
  end

  public fun patch(self, path: string, body: string) -> Reply
    self.send("PATCH", path, body)
  end

  --" `POST` of an HTML form: the fields as `application/x-www-form-urlencoded`. --"
  public fun post_form(self, path: string, fields: map<string, string>) -> Reply
    let pairs: array<string> = []
    for name in fields.keys() do
      pairs.push("{Url.encode(name)}={Url.encode(fields[name] ?? "")}")
    end
    let sent = self.build("POST", path, pairs.join("&"))
    sent.headers["content-type"] = "application/x-www-form-urlencoded"
    self.deliver(sent)
  end

  --" `POST` with `value` as a JSON body. --"
  public fun post_json<T>(self, path: string, value: T) -> Reply
    self.send_json<T>("POST", path, value)
  end

  public fun put_json<T>(self, path: string, value: T) -> Reply
    self.send_json<T>("PUT", path, value)
  end

  public fun send_json<T>(self, method: string, path: string, value: T) -> Reply
    let text = Json.of(value).to_text()
    let sent = self.build(method, path, text)
    sent.headers["content-type"] = "application/json"
    self.deliver(sent)
  end

  --" Sends a request. A query string in `path` is read as the server would. --"
  public fun send(self, method: string, path: string, body: string?) -> Reply
    self.deliver(self.build(method, path, body))
  end

  fun build(self, method: string, path: string, body: string?) -> Request
    let query: map<string, string> = {}
    let all: map<string, array<string>> = {}
    let clean = path
    let at = path.index_of("?")
    if at != none then
      clean = path.substring(0, at)
      for pair in path.substring(at + 1, path.len()).split("&") do
        if pair == "" then
          continue
        end
        let kv = pair.split("=")
        let key = Url.decode(kv[0]) ?? kv[0]
        let value = if kv.len() > 1 then Url.decode(kv[1]) ?? kv[1] else "" end
        query[key] = value
        let seen = all[key]
        if seen == none then
          all[key] = [value]
        else
          seen.push(value)
        end
      end
    end
    let headers: map<string, string> = {}
    for name in self.headers.keys() do
      headers[name] = self.headers[name] ?? ""
    end
    let cookies: map<string, string> = {}
    for name in self.cookies.keys() do
      cookies[name] = self.cookies[name] ?? ""
    end
    Request { method: method.upper(), url: path, path: clean, query: query, query_all: all, headers: headers, body: body, cookies: cookies }
  end

  fun deliver(self, req: Request) -> Reply
    if self.cookies.len() > 0 then
      let parts: array<string> = []
      for name in self.cookies.keys() do
        parts.push("{name}={self.cookies[name] ?? ""}")
      end
      req.headers["cookie"] = parts.join("; ")
    end
    let res = self.app.handle(req)
    for c in res.cookies do
      let age = c.max_age
      if age != none and age <= 0 then
        self.cookies.remove(c.name)
      else
        self.cookies[c.name] = c.value
      end
    end
    Reply { status: res.status, headers: res.headers, body: res.body, cookies: res.cookies }
  end
end

export Client, Reply

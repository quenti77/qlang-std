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

  --" The request this client would send (its headers and cookies included), without sending it. --"
  public fun request(self, method: string, path: string, body: string?) -> Request
    self.build(method, path, body)
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
    let text = body
    let raw: bytes? = if text == none then none else text.to_bytes() end
    Request { method: method.upper(), url: path, path: clean, query: query, query_all: all, headers: headers, body: body, raw: raw, cookies: cookies }
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

--" A WebSocket opened on an application without a network: what the server does is done here, one
event at a time. The callbacks run in the test, so what they write is read with `received`.

```
let a = WsClient.open(app, "/chat?name=ada")
a.received()              -- ["welcome ada"]
a.send("hi")
a.received()              -- what the handler answered
```
--"
struct WsClient
  public conn: WebSocket
  handler: WebSocketHandler
  pending: array<WsFrame>
end

impl WsClient
  --" Opens the WebSocket of `path`; stops the test if the route does not answer with one. --"
  public fun open(app: web.App, path: string) -> WsClient
    let r = WsClient.try_open(app, path, {})
    if r.is_err() then
      panic(r.unwrap_err().message)
    end
    r.unwrap()
  end

  --" Like `open`, with extra headers (`origin`, `authorization`); `err` says why it did not open
  (the status the route answered with, for example). --"
  public fun try_open(app: web.App, path: string, headers: map<string, string>) -> Result<WsClient, Error>
    let req = Client.new(app).request("GET", path, none)
    req.headers["upgrade"] = "websocket"
    req.headers["connection"] = "Upgrade"
    req.headers["sec-websocket-version"] = "13"
    req.headers["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ=="
    for name in headers.keys() do
      req.headers[name.lower()] = headers[name] ?? ""
    end
    let res = app.handle(req)
    let handler = res.websocket
    if handler == none then
      return Result<WsClient, Error>.Err(Error { message: "not a WebSocket: the route answered {res.status} {res.body}" })
    end
    let token = Crypto.token(6)
    let id = if token.is_ok() then token.unwrap() else "x" end
    let conn = WebSocket { id: "test-{id}", request: req }
    let client = WsClient { conn: conn, handler: handler, pending: [] }
    let on_open = handler.on_open
    if on_open != none then
      on_open(conn)
    end
    client.collect()
    Result<WsClient, Error>.Ok(client)
  end

  fun collect(self)
    for f in self.conn.take_frames() do
      self.pending.push(f)
    end
  end

  --" The client sends a text message. --"
  public fun send(self, text: string)
    self.handler.on_message(self.conn, WsMessage { text: text })
    self.collect()
  end

  --" The client sends a binary message. --"
  public fun send_bytes(self, data: bytes)
    self.handler.on_message(self.conn, WsMessage { data: data, binary: true })
    self.collect()
  end

  --" The time for `on_tick` came. --"
  public fun tick(self)
    let on_tick = self.handler.on_tick
    if on_tick != none then
      on_tick(self.conn)
    end
    self.collect()
  end

  --" The texts the server sent since the last call. --"
  public fun received(self) -> array<string>
    self.collect()
    let out: array<string> = []
    for f in self.pending do
      if f.kind == "text" then
        out.push(f.text)
      end
    end
    self.pending = []
    out
  end

  --" Every frame the server sent since the last call (texts, binaries, a close). --"
  public fun frames(self) -> array<WsFrame>
    self.collect()
    let out = self.pending
    self.pending = []
    out
  end

  --" The client leaves: `on_close` runs. --"
  public fun close(self)
    let was_open = self.conn.is_open()
    self.conn.close()
    let on_close = self.handler.on_close
    if was_open and on_close != none then
      on_close(self.conn)
    end
    self.collect()
  end

  --" Whether the connection is still open (the server may have closed it). --"
  public fun is_open(self) -> bool
    self.conn.is_open()
  end
end

export Client, Reply, WsClient

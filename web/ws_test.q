import "app.q" as web
import "ws.q" as ws
import "testing.q" as testing

#[web.Get("/chat")]
#[web.Guard("origin")]
fun chat(req: Request, hub: ws.Hub) -> Response
  let name = req.query["name"] ?? "anon"
  Response.websocket(WebSocketHandler {
    on_open: fun(c: WebSocket)
      hub.join("lobby", c)
      c.send("welcome {name}")
    end,
    on_message: fun(c: WebSocket, m: WsMessage)
      hub.broadcast("lobby", "{name}: {m.text ?? ""}", c.id)
      c.send("sent")
    end,
    on_close: fun(c: WebSocket) hub.leave(c) end,
  })
end

fun build() -> web.App
  let app = web.App.new([])
  let hub = ws.Hub.new()
  app.container.set(hub)
  app.guard("origin", ws.origin_guard(["https://app.example"]))
  app.controllers([Reflect.callable("chat") ?? panic("missing")])
  app
end

fun test_a_client_opens_a_websocket_and_hears_the_others()
  let app = build()
  let a = testing.WsClient.open(app, "/chat?name=ada")
  assert_eq(a.received(), ["welcome ada"])
  let b = testing.WsClient.open(app, "/chat?name=bob")
  assert_eq(b.received(), ["welcome bob"])
  a.send("hi")
  assert_eq(a.received(), ["sent"])
  assert_eq(b.received(), ["ada: hi"])
  b.close()
  assert_eq(b.is_open(), false)
end

fun test_a_guard_refuses_before_the_upgrade()
  let app = build()
  let refused = testing.WsClient.try_open(app, "/chat", {"origin": "https://evil.example"})
  assert_eq(refused.is_err(), true)
  assert(refused.unwrap_err().message.contains("403"))
  assert_eq(testing.WsClient.try_open(app, "/chat", {"origin": "https://app.example"}).is_ok(), true)
end

fun test_a_route_that_is_not_a_websocket_is_reported()
  let app = web.App.new([])
  app.get("/plain", fun(r: Request) -> Response Response.text("x") end)
  assert_eq(testing.WsClient.try_open(app, "/plain", {}).is_err(), true)
end

fun test_the_bus_shares_messages_between_connections_through_the_database()
  let bus = ws.Bus.new(Db.connect("sqlite://:memory:").unwrap(), "sqlite")
  let clock = [1000000]
  bus.clock = fun() -> int clock[0] end
  bus.install().unwrap()
  bus.publish("news", "old").unwrap()
  let handler = WebSocketHandler {
    on_message: fun(c: WebSocket, m: WsMessage) bus.publish("news", m.text ?? "").unwrap() end,
    on_tick: fun(c: WebSocket) bus.deliver(c, "news") end,
  }
  let make = fun(id: string) -> WebSocket
    WebSocket { id: id, request: Request { method: "GET", url: "/", path: "/" } }
  end
  let a = make("a")
  let b = make("b")
  -- the first tick of a connection only notes where the room stands: it hears what comes after
  bus.deliver(a, "news")
  assert_eq(a.take_frames().len(), 0)
  bus.deliver(b, "news")
  bus.publish("news", "one").unwrap()
  bus.publish("news", "two").unwrap()
  bus.deliver(a, "news")
  bus.deliver(b, "news")
  assert_eq(a.take_frames().map(fun(f: WsFrame) -> string f.text end), ["one", "two"])
  assert_eq(b.take_frames().map(fun(f: WsFrame) -> string f.text end), ["one", "two"])
  bus.deliver(a, "news")
  assert_eq(a.take_frames().len(), 0)
  clock[0] += 3600000
  assert_eq(bus.prune(60).unwrap(), 3)
end

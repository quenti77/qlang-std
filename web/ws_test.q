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

fun test_a_relay_reads_the_bus_once_for_all_the_connections_of_a_worker()
  let db = Db.connect("sqlite://:memory:").unwrap()
  let bus = ws.Bus.new(db, "sqlite")
  let clock = [1000000]
  bus.clock = fun() -> int clock[0] end
  bus.install().unwrap()
  let hub = ws.Hub.new()
  let relay = ws.Relay.new(bus, hub, 250)
  let handler = WebSocketHandler {
    on_open: fun(c: WebSocket)
      hub.join("lobby", c)
      relay.watch("lobby")
    end,
    on_message: fun(c: WebSocket, m: WsMessage) bus.publish("lobby", m.text ?? "").unwrap() end,
    on_tick: fun(c: WebSocket) relay.pump() end,
  }
  let make = fun(id: string) -> WebSocket
    WebSocket { id: id, request: Request { method: "GET", url: "/", path: "/" } }
  end
  let a = make("a")
  let b = make("b")
  let join = fun(c: WebSocket)
    hub.join("lobby", c)
    relay.watch("lobby")
  end
  join(a)
  join(b)
  let say = handler.on_message
  -- the first read happens at once: nothing yet
  assert_eq(relay.pump(), 0)
  say(a, WsMessage { text: "hello" })
  -- not due yet: nothing is read
  assert_eq(relay.pump(), 0)
  clock[0] += 300
  assert_eq(relay.pump(), 1)
  let texts = fun(c: WebSocket) -> array<string> c.take_frames().map(fun(f: WsFrame) -> string f.text end) end
  assert_eq(texts(a), ["hello"])
  assert_eq(texts(b), ["hello"])
  -- nothing new: the next read finds nothing
  clock[0] += 300
  assert_eq(relay.pump(), 0)
  -- a room nobody listens to is not read, and what was said meanwhile is not replayed
  hub.leave(a)
  hub.leave(b)
  say(a, WsMessage { text: "to nobody" })
  clock[0] += 300
  assert_eq(relay.pump(), 0)
  join(b)
  clock[0] += 300
  assert_eq(relay.pump(), 0)
  assert_eq(b.take_frames().len(), 0)
end

--" Needs a server: QLANG_TEST_REDIS (see queue_redis_test.q). --"
fun test_redis_pushes_messages_to_every_worker_without_any_query()
  let url = env.get("QLANG_TEST_REDIS")
  if url == none then
    return
  end
  let publisher = Redis.connect(url).unwrap()
  let bus = ws.RedisBus.new(publisher, "wst:")
  -- two workers: each has its hub, its subscription and its relay
  let hub_a = ws.Hub.new()
  let hub_b = ws.Hub.new()
  let relay_a = ws.Relay.with_feed(ws.RedisFeed.open(url, "wst:").unwrap(), hub_a, 0)
  let relay_b = ws.Relay.with_feed(ws.RedisFeed.open(url, "wst:").unwrap(), hub_b, 0)
  let make = fun(id: string) -> WebSocket
    WebSocket { id: id, request: Request { method: "GET", url: "/", path: "/" } }
  end
  let a = make("a")
  let b = make("b")
  hub_a.join("lobby", a)
  relay_a.watch("lobby")
  hub_b.join("lobby", b)
  relay_b.watch("lobby")
  assert_eq(bus.publish("lobby", "hello").unwrap(), 2)
  assert_eq(bus.publish("other", "ignored").unwrap(), 0)
  -- the message is on its way: look for it for up to a second
  let heard = [0, 0]
  let tries = 0
  while (heard[0] == 0 or heard[1] == 0) and tries < 100 do
    heard[0] += relay_a.pump()
    heard[1] += relay_b.pump()
    time.sleep(10)
    tries += 1
  end
  assert_eq(a.take_frames().map(fun(f: WsFrame) -> string f.text end), ["hello"])
  assert_eq(b.take_frames().map(fun(f: WsFrame) -> string f.text end), ["hello"])
end

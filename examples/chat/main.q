-- A chat room that works with several workers:
--   CHAT_DB=sqlite://chat.db qlang serve examples/chat/main.q --workers 2
-- or with Redis, which pushes the messages (no query while nobody speaks):
--   CHAT_REDIS=redis://127.0.0.1:6379 qlang serve examples/chat/main.q --workers 2
-- then open http://localhost:8080 in two browser tabs.
import "../../web/app.q" as web
import "../../web/ws.q" as ws

-- the page is a file next to this one (its braces are not qlang strings)
const PAGE = fs.read("examples/chat/index.html").unwrap()

-- How the messages travel between workers: Redis if CHAT_REDIS is set, else a table in the database.
struct Transport
  public relay: ws.Relay
  public publish: fun(string)
end

fun connect(hub: ws.Hub) -> Transport
  let redis_url = env.get("CHAT_REDIS")
  if redis_url != none then
    let bus = ws.RedisBus.new(Redis.connect(redis_url).unwrap(), "chat:")
    return Transport {
      relay: ws.Relay.with_feed(ws.RedisFeed.open(redis_url, "chat:").unwrap(), hub, 50),
      publish: fun(text: string) bus.publish("lobby", text) end,
    }
  end
  let bus = ws.Bus.new(Db.connect(env.get("CHAT_DB") ?? "sqlite://:memory:").unwrap(), "sqlite")
  bus.install().unwrap()
  Transport {
    relay: ws.Relay.new(bus, hub, 250),
    publish: fun(text: string) bus.publish("lobby", text) end,
  }
end

-- the connections of this worker, and one read of the messages for all of them
let hub = ws.Hub.new()
let transport = connect(hub)
let relay = transport.relay
let publish = transport.publish

let app = web.App.new([])
app.get("/", fun(req: Request) -> Response Response.html(PAGE) end)
app.get("/ws", fun(req: Request) -> Response
  let name = req.query["name"] ?? "anon"
  Response.websocket(WebSocketHandler {
    tick_ms: 50,
    on_open: fun(c: WebSocket)
      hub.join("lobby", c)
      relay.watch("lobby")
      publish("{name} joined")
    end,
    on_message: fun(c: WebSocket, m: WsMessage)
      let text = (m.text ?? "").trim()
      if not text.is_empty() and text.len() <= 500 then
        publish("{name}: {text}")
      end
    end,
    on_tick: fun(c: WebSocket) relay.pump() end,
    on_close: fun(c: WebSocket) hub.leave(c) end,
  })
end)

fun handle(req: Request) -> Response
  app.handle(req)
end

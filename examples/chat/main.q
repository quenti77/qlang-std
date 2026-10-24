-- A chat room that works with several workers:
--   CHAT_DB=sqlite://chat.db qlang serve examples/chat/main.q --workers 2
-- then open http://localhost:8080 in two browser tabs.
import "../../web/app.q" as web
import "../../web/ws.q" as ws

-- the page is a file next to this one (its braces are not qlang strings)
const PAGE = fs.read("examples/chat/index.html").unwrap()

let db = Db.connect(env.get("CHAT_DB") ?? "sqlite://:memory:").unwrap()
let bus = ws.Bus.new(db, "sqlite")
bus.install().unwrap()

let app = web.App.new([])
app.get("/", fun(req: Request) -> Response Response.html(PAGE) end)
app.get("/ws", fun(req: Request) -> Response
  let name = req.query["name"] ?? "anon"
  Response.websocket(WebSocketHandler {
    tick_ms: 300,
    on_open: fun(c: WebSocket)
      bus.deliver(c, "lobby")
      bus.publish("lobby", "{name} joined").unwrap()
    end,
    on_message: fun(c: WebSocket, m: WsMessage)
      let text = (m.text ?? "").trim()
      if not text.is_empty() and text.len() <= 500 then
        bus.publish("lobby", "{name}: {text}").unwrap()
      end
    end,
    on_tick: fun(c: WebSocket) bus.deliver(c, "lobby") end,
  })
end)

fun handle(req: Request) -> Response
  app.handle(req)
end

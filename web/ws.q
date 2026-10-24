--" # WebSockets

A route turns the connection into a WebSocket by returning `Response.websocket(...)`:

```
#[web.Get("/chat")]
#[web.Guard("auth")]
fun chat(req: Request, who: Me) -> Response
  Response.websocket(WebSocketHandler {
    on_open: fun(c: WebSocket) hub.join("lobby", c) end,
    on_message: fun(c: WebSocket, m: WsMessage) hub.broadcast("lobby", "{who.email}: {m.text ?? ""}", none) end,
    on_close: fun(c: WebSocket) hub.leave(c) end,
  })
end
```

The guards and middleware of the route run first, like for any request (a guard refuses with `401` before
the connection is upgraded). **Check the `Origin` header** (`origin_guard`): a browser lets any page open a
WebSocket to your server with the visitor's cookies.

Each worker serves many connections between two requests, so a callback must be short: never wait in it.
A worker does not see the connections of the other workers (`--workers 4` starts four programs that share
nothing). Two tools cover that:

- `Hub` keeps the connections of **one worker** in rooms: `join`, `leave`, `broadcast`. Use it with
  `--workers 1`, or for what only concerns the connection itself.
- Every worker gets a `Relay` (a `Hub` plus a *feed*): it brings the messages to the connections of its
  worker with **one read per interval and room**, whatever the number of connections, and fans them out
  in memory. Two feeds:
  - `Bus` + `DbFeed` go through the **database**: `bus.publish(room, text)` writes a row and every relay
    reads the new rows. Nothing else to run; a relay interval of a few hundred milliseconds feels instant
    for a chat. (`Bus.deliver` reads once per *connection*: fine for a few dozen, no more.)
  - `RedisBus` + `RedisFeed` go through **Redis** publish/subscribe: each worker subscribes once per
    room and Redis pushes the messages, so nothing is read while nobody speaks, and the interval can be
    50 ms. This is what a real deployment (Laravel Reverb, Socket.IO adapters...) does.
--"
import "app.q" as web

--" The connections of one worker, in rooms. --"
struct Hub
  public rooms: map<string, array<WebSocket>>
end

impl Hub
  public fun new() -> Hub
    Hub { rooms: {} }
  end

  --" Puts the connection in a room. --"
  public fun join(self, room: string, conn: WebSocket)
    let members = self.rooms[room]
    if members == none then
      self.rooms[room] = [conn]
    else
      members.push(conn)
    end
  end

  --" Takes the connection out of every room. Call it in `on_close`. --"
  public fun leave(self, conn: WebSocket)
    for room in self.rooms.keys() do
      let members = self.rooms[room] ?? []
      let kept: array<WebSocket> = []
      for m in members do
        if m.id != conn.id then
          kept.push(m)
        end
      end
      self.rooms[room] = kept
    end
  end

  --" How many connections are in the room. --"
  public fun count(self, room: string) -> int
    (self.rooms[room] ?? []).filter(fun(c: WebSocket) -> bool c.is_open() end).len()
  end

  --" Sends a text to everybody in the room except `except` (a connection id, or `none`).
  Gives how many received it. --"
  public fun broadcast(self, room: string, text: string, except: string?) -> int
    let sent = 0
    for m in self.rooms[room] ?? [] do
      if m.is_open() and (except == none or m.id != except) then
        m.send(text)
        sent += 1
      end
    end
    sent
  end
end

--" Messages shared by every worker through a table. --"
struct Bus
  public db: Db
  public table: string
  public dialect: string
  --" The time in milliseconds; tests give their own. --"
  public clock: fun() -> int
end

impl Bus
  --" A bus on `db`; `dialect` is `"sqlite"`, `"postgres"` or `"mysql"`. --"
  public fun new(db: Db, dialect: string) -> Bus
    Bus { db: db, table: "ws_messages", dialect: dialect, clock: fun() -> int time.now() end }
  end

  --" Makes the table if it does not exist. --"
  public fun install(self) -> Result<bool, Error>
    let id = if self.dialect == "postgres" then "BIGSERIAL PRIMARY KEY" else (if self.dialect == "mysql" then "BIGINT AUTO_INCREMENT PRIMARY KEY" else "INTEGER PRIMARY KEY AUTOINCREMENT" end) end
    let made = self.db.execute("CREATE TABLE IF NOT EXISTS {self.table} (id {id}, room VARCHAR(255) NOT NULL, payload TEXT NOT NULL, created_at BIGINT NOT NULL)", [])
    if made.is_err() then
      return Result<bool, Error>.Err(made.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" Writes a message for the room. --"
  public fun publish(self, room: string, text: string) -> Result<bool, Error>
    let saved = self.db.execute("INSERT INTO {self.table} (room, payload, created_at) VALUES (?, ?, ?)", [Json.string(room), Json.string(text), Json.number(self.clock() as float)])
    if saved.is_err() then
      return Result<bool, Error>.Err(saved.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" The number of the last message of the room (0 if none): where a new connection starts, so
  that it only hears what comes after. --"
  public fun last(self, room: string) -> int
    let rows = self.db.query("SELECT MAX(id) AS last FROM {self.table} WHERE room = ?", [Json.string(room)])
    if rows.is_err() or rows.unwrap().is_empty() then
      return 0
    end
    let n = rows.unwrap()[0].get("last", Json.null())
    if n.is_null() then 0 else n.as_number() as int end
  end

  --" The messages of the room after number `after`, oldest first, as (number, text). --"
  public fun since(self, room: string, after: int) -> array<(int, string)>
    let out: array<(int, string)> = []
    let rows = self.db.query("SELECT id, payload FROM {self.table} WHERE room = ? AND id > ? ORDER BY id ASC LIMIT 200", [Json.string(room), Json.number(after as float)])
    if rows.is_err() then
      Log.error("bus: {rows.unwrap_err().message}")
      return out
    end
    for r in rows.unwrap() do
      out.push((r.get("id", Json.null()).as_number() as int, r.get("payload", Json.null()).as_string()))
    end
    out
  end

  --" Sends to the connection what was published in the room since the last time it was asked
  (`conn.data["cursor:room"]` remembers where it stopped). Call it from `on_tick`. --"
  public fun deliver(self, conn: WebSocket, room: string)
    let key = "cursor:{room}"
    let held = conn.data[key]
    let after = if held == none then self.last(room) else (held.as<int>() ?? 0) end
    if held == none then
      conn.data[key] = Any.of(after)
      return
    end
    let news = self.since(room, after)
    for m in news do
      conn.send(m.1)
      conn.data[key] = Any.of(m.0)
    end
  end

  --" Deletes the messages older than `seconds`. Run it from time to time. --"
  public fun prune(self, seconds: int) -> Result<int, Error>
    self.db.execute("DELETE FROM {self.table} WHERE created_at < ?", [Json.number((self.clock() - seconds * 1000) as float)])
  end
end

--" Where a `Relay` takes the messages from: the database (`DbFeed`) or Redis (`RedisFeed`). --"
trait Feed
  --" Starts listening to a room: only what is published from now on is delivered. --"
  fun watch(self, room: string)
  --" The messages that arrived since the last call, as (room, text). `active` are the rooms that have
  members here: a feed may skip the others. --"
  fun pull(self, active: array<string>) -> array<(string, string)>
end

--" The messages of a `Bus` (the database), read after the last one seen in each room. --"
struct DbFeed
  public bus: Bus
  cursors: map<string, int>
end

impl DbFeed
  public fun new(bus: Bus) -> DbFeed
    DbFeed { bus: bus, cursors: {} }
  end
end

impl Feed for DbFeed
  public fun watch(self, room: string)
    if self.cursors[room] == none then
      self.cursors[room] = self.bus.last(room)
    end
  end

  public fun pull(self, active: array<string>) -> array<(string, string)>
    let out: array<(string, string)> = []
    for room in self.cursors.keys() do
      if not active.contains(room) then
        -- nobody here listens: skip the read, and start again from the end when someone joins
        self.cursors[room] = self.bus.last(room)
        continue
      end
      for m in self.bus.since(room, self.cursors[room] ?? 0) do
        out.push((room, m.1))
        self.cursors[room] = m.0
      end
    end
    out
  end
end

--" The messages of Redis channels (`ws:{room}`): the worker subscribes once per room, Redis pushes the
messages, and `pull` only reads what already arrived: no query at all while nothing is said. --"
struct RedisFeed
  public sub: Subscription
  public prefix: string
  watched: array<string>
end

impl RedisFeed
  --" Opens the connection that listens. Channels are named `{prefix}{room}`. --"
  public fun open(url: string, prefix: string) -> Result<RedisFeed, Error>
    let sub = Redis.subscriber(url, [])
    if sub.is_err() then
      return Result<RedisFeed, Error>.Err(sub.unwrap_err())
    end
    Result<RedisFeed, Error>.Ok(RedisFeed { sub: sub.unwrap(), prefix: prefix, watched: [] })
  end
end

impl Feed for RedisFeed
  public fun watch(self, room: string)
    if not self.watched.contains(room) then
      let r = self.sub.subscribe([self.prefix + room])
      if r.is_err() then
        Log.error("ws: {r.unwrap_err().message}")
        return
      end
      self.watched.push(room)
    end
  end

  public fun pull(self, active: array<string>) -> array<(string, string)>
    let out: array<(string, string)> = []
    let count = 0
    while count < 500 do
      let m = self.sub.next(0)
      if m.is_err() then
        Log.error("ws: {m.unwrap_err().message}")
        break
      end
      let msg = m.unwrap()
      if msg == none then
        break
      end
      if msg.channel.starts_with(self.prefix) then
        out.push((msg.channel.substring(self.prefix.len(), msg.channel.len()), msg.payload))
      end
      count += 1
    end
    out
  end
end

--" Publishes to the Redis channels a `RedisFeed` listens to. --"
struct RedisBus
  public redis: Redis
  public prefix: string
end

impl RedisBus
  public fun new(redis: Redis, prefix: string) -> RedisBus
    RedisBus { redis: redis, prefix: prefix }
  end

  --" Sends a text to the room, on every worker of every machine. Gives how many workers listen. --"
  public fun publish(self, room: string, text: string) -> Result<int, Error>
    self.redis.publish(self.prefix + room, text)
  end
end

--" Brings what a feed holds to the connections of **this worker**, with one read per room and
interval whatever the number of connections (none at all with Redis, which pushes): the read is
shared, the fan-out is in memory (through a `Hub`). Make one per worker, next to the hub.

```
let hub = ws.Hub.new()
let relay = ws.Relay.new(bus, hub, 250)                   -- a bus in the database
-- or: let relay = ws.Relay.with_feed(redis_feed, hub, 50)   -- Redis
-- in the handler:
on_open: fun(c: WebSocket)
  hub.join("lobby", c)
  relay.watch("lobby")
end,
on_tick: fun(c: WebSocket) relay.pump() end,
```

Every connection may call `pump` from its tick: the call returns at once unless the interval has
passed since the last read. A worker with 1 000 connections still makes `1000 / interval` cheap calls
and one read per room each `interval`, instead of one query per connection. --"
struct Relay
  public feed: Feed
  public hub: Hub
  public interval: int
  --" The time in milliseconds; tests give their own. --"
  public clock: fun() -> int
  last: int
end

impl Relay
  --" A relay on the bus in the database; `interval` is the number of milliseconds between two reads. --"
  public fun new(bus: Bus, hub: Hub, interval: int) -> Relay
    let r = Relay.with_feed(DbFeed.new(bus), hub, interval)
    r.clock = bus.clock
    r
  end

  public fun with_feed(feed: Feed, hub: Hub, interval: int) -> Relay
    Relay { feed: feed, hub: hub, interval: interval, clock: fun() -> int time.now() end, last: 0 }
  end

  --" Starts listening to a room. --"
  public fun watch(self, room: string)
    self.feed.watch(room)
  end

  --" Reads the new messages (if the interval passed) and sends them to the members of the hub.
  Gives how many messages were read. --"
  public fun pump(self) -> int
    let now = self.clock()
    if now - self.last < self.interval then
      return 0
    end
    self.last = now
    let active = self.hub.rooms.keys().filter(fun(r: string) -> bool self.hub.count(r) > 0 end)
    let read = 0
    for m in self.feed.pull(active) do
      self.hub.broadcast(m.0, m.1, none)
      read += 1
    end
    read
  end
end

--" A guard that only lets through the requests whose `Origin` is one of these (or that have none,
which is the case of programs that are not browsers). Register it with `app.guard("origin", ...)`
and put `#[web.Guard("origin")]` on the WebSocket route. --"
fun origin_guard(allowed: array<string>) -> web.GuardFn
  fun(req: Request) -> Response?
    let origin = req.header("origin")
    if origin == none or allowed.contains(origin) then
      return none
    end
    web.Problem { status: 403, message: "origin not allowed" }.to_response()
  end
end

export Hub, Bus, Feed, DbFeed, RedisFeed, RedisBus, Relay, origin_guard

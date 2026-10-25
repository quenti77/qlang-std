--" # Notifications

One message, several places: an email, a post in Slack or Discord, a line in the user's in-app inbox.

```
let notifier = Notifier.new()
notifier.channel("mail", MailChannel { mailer: mailer, sender: "App <app@example.org>" })
notifier.channel("slack", WebhookChannel.slack(env.get("SLACK_URL") ?? ""))
notifier.channel("inbox", inbox)                         -- an InboxChannel, see below

notifier.send(["mail", "inbox"], "ada@example.org", Notification { kind: "invoice", title: "Invoice paid", body: "Thank you." })
```

`send` tries every channel and says which failed; a channel that fails never stops the others. For the
inbox, `to` is the id of the user; for a mail, an address; a webhook ignores it. Put `notifier.send` in a
job (`queue.push`) so a slow service does not slow an answer.
--"
import "mail.q" as mail

--" What is told. --"
struct Notification
  --" A short name for the sort of event (`invoice`, `comment`): the inbox keeps it. --"
  public kind: string
  public title: string
  public body: string = ""
  --" A page to open, if any. --"
  public url: string = ""
end

--" A place where notifications go. --"
trait Channel
  fun deliver(self, to: string, n: Notification) -> Result<bool, Error>
end

fun notify_error<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
end

--" Sends an email (`to` is the address). --"
struct MailChannel
  public mailer: mail.Mailer
  public sender: string
end

impl Channel for MailChannel
  public fun deliver(self, to: string, n: Notification) -> Result<bool, Error>
    let text = if n.url == "" then n.body else "{n.body}\n\n{n.url}" end
    self.mailer.send(mail.Mail { sender: self.sender, to: [to], subject: n.title, text: text })
  end
end

--" Posts to a chat webhook. --"
struct WebhookChannel
  public url: string
  --" `slack` (`{"text": ...}`), `discord` (`{"content": ...}`) or `json` (the notification itself). --"
  public format: string
  public transport: fun(Request) -> Result<Response, Error>
end

impl WebhookChannel
  public fun slack(url: string) -> WebhookChannel
    WebhookChannel { url: url, format: "slack", transport: fun(r: Request) -> Result<Response, Error> http.send(r) end }
  end

  public fun discord(url: string) -> WebhookChannel
    WebhookChannel { url: url, format: "discord", transport: fun(r: Request) -> Result<Response, Error> http.send(r) end }
  end

  public fun json(url: string) -> WebhookChannel
    WebhookChannel { url: url, format: "json", transport: fun(r: Request) -> Result<Response, Error> http.send(r) end }
  end
end

impl Channel for WebhookChannel
  public fun deliver(self, to: string, n: Notification) -> Result<bool, Error>
    let head = if n.body == "" then n.title else "{n.title}\n{n.body}" end
    let line = if n.url == "" then head else "{head}\n{n.url}" end
    let body = if self.format == "slack" then Json.object({"text": Json.string(line)}).to_text() else (if self.format == "discord" then Json.object({"content": Json.string(line)}).to_text() else Json.of(n).to_text() end) end
    let r = self.transport(Request { method: "POST", url: self.url, headers: {"Content-Type": "application/json"}, body: body })
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    if r.unwrap().status >= 300 then
      return notify_error<bool>("the webhook answered {r.unwrap().status}")
    end
    Result<bool, Error>.Ok(true)
  end
end

--" One line of the inbox. --"
struct InboxItem
  public id: int
  public user_id: string
  public kind: string
  public title: string
  public body: string
  public url: string
  public created_at: int
  public read_at: int?
end

--" The in-app inbox of each user, in a table. --"
struct InboxChannel
  public db: Db
  public dialect: string
  public table: string = "notifications"
  --" The time in milliseconds; tests give their own. --"
  public clock: fun() -> int
end

impl InboxChannel
  public fun new(db: Db, dialect: string) -> InboxChannel
    InboxChannel { db: db, dialect: dialect, table: "notifications", clock: fun() -> int time.now() end }
  end

  public fun install(self) -> Result<bool, Error>
    let id = if self.dialect == "postgres" then "BIGSERIAL PRIMARY KEY" else (if self.dialect == "mysql" then "BIGINT AUTO_INCREMENT PRIMARY KEY" else "INTEGER PRIMARY KEY AUTOINCREMENT" end) end
    let made = self.db.execute("CREATE TABLE IF NOT EXISTS {self.table} (id {id}, user_id VARCHAR(190) NOT NULL, kind VARCHAR(100) NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, url TEXT NOT NULL, created_at BIGINT NOT NULL, read_at BIGINT)", [])
    if made.is_err() then
      return Result<bool, Error>.Err(made.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" The newest notifications of a user (`limit` of them). --"
  public fun list(self, user: string, limit: int) -> Result<array<InboxItem>, Error>
    let rows = self.db.query("SELECT id, user_id, kind, title, body, url, created_at, read_at FROM {self.table} WHERE user_id = ? ORDER BY id DESC LIMIT {limit}", [Json.string(user)])
    if rows.is_err() then
      return Result<array<InboxItem>, Error>.Err(rows.unwrap_err())
    end
    let out: array<InboxItem> = []
    for row in rows.unwrap() do
      let item = Json.to<InboxItem>(Json.object(row))
      if item.is_err() then
        return Result<array<InboxItem>, Error>.Err(item.unwrap_err())
      end
      out.push(item.unwrap())
    end
    Result<array<InboxItem>, Error>.Ok(out)
  end

  public fun unread_count(self, user: string) -> Result<int, Error>
    let rows = self.db.query("SELECT COUNT(*) AS n FROM {self.table} WHERE user_id = ? AND read_at IS NULL", [Json.string(user)])
    if rows.is_err() then
      return Result<int, Error>.Err(rows.unwrap_err())
    end
    Result<int, Error>.Ok(rows.unwrap()[0].get("n", Json.null()).as_number() as int)
  end

  --" Marks one notification of the user as read (a user cannot mark another's). --"
  public fun mark_read(self, user: string, id: int) -> Result<bool, Error>
    let changed = self.db.execute("UPDATE {self.table} SET read_at = ? WHERE id = ? AND user_id = ? AND read_at IS NULL", [Json.number(self.clock() as float), Json.number(id as float), Json.string(user)])
    if changed.is_err() then
      return Result<bool, Error>.Err(changed.unwrap_err())
    end
    Result<bool, Error>.Ok(changed.unwrap() == 1)
  end

  public fun mark_all_read(self, user: string) -> Result<int, Error>
    self.db.execute("UPDATE {self.table} SET read_at = ? WHERE user_id = ? AND read_at IS NULL", [Json.number(self.clock() as float), Json.string(user)])
  end
end

impl Channel for InboxChannel
  public fun deliver(self, to: string, n: Notification) -> Result<bool, Error>
    let saved = self.db.execute("INSERT INTO {self.table} (user_id, kind, title, body, url, created_at) VALUES (?, ?, ?, ?, ?, ?)", [Json.string(to), Json.string(n.kind), Json.string(n.title), Json.string(n.body), Json.string(n.url), Json.number(self.clock() as float)])
    if saved.is_err() then
      return Result<bool, Error>.Err(saved.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end
end

--" The channels of the application, by name. --"
struct Notifier
  public channels: map<string, Channel>
end

impl Notifier
  public fun new() -> Notifier
    Notifier { channels: {} }
  end

  public fun channel(self, name: string, c: Channel)
    self.channels[name] = c
  end

  --" Sends on each named channel. Gives the errors, one per channel that failed (an empty list: all went well).
  An unknown channel name is an error too. --"
  public fun send(self, names: array<string>, to: string, n: Notification) -> array<string>
    let failures: array<string> = []
    for name in names do
      let c = self.channels[name]
      if c == none then
        failures.push("{name}: no such channel")
        continue
      end
      let r = c.deliver(to, n)
      if r.is_err() then
        failures.push("{name}: {r.unwrap_err().message}")
        Log.warn("notification on {name} failed: {r.unwrap_err().message}")
      end
    end
    failures
  end
end

export Notification, Channel, MailChannel, WebhookChannel, InboxChannel, InboxItem, Notifier

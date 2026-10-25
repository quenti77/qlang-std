--" # Mail

Sends an email through the HTTP API of a mail service (Resend, Postmark, SendGrid, Mailgun), with the
`http.send` of the language: nothing to install, and a transport is a value you can swap in a test.

```
let mailer: Mailer = ResendMailer.new(env.get("RESEND_KEY") ?? "")
let sent = mailer.send(Mail {
  sender: "Blog <blog@example.org>",
  to: ["ada@example.org"],
  subject: "Welcome",
  text: "Hello Ada",
  html: "<p>Hello <b>Ada</b></p>",
})
```

`MemoryMailer` keeps what was sent (for tests) and `LogMailer` writes it in the log (for development).
A mail is sent while the request waits: from a route, put it in the job queue (`SendMail` job, see `queue.q`)
so a slow service never slows an answer.

Addresses and subjects are checked: a line break in them is an error, never a second header (the "header
injection" of badly written mailers). An SMTP client is not provided: the language has no raw sockets; every
mail service has an HTTP API.
--"

import "queue.q" as qq

--" An email. `text` and `html` are two versions of the body: give at least one. --"
struct Mail
  --" `Name <address>` or `address`. --"
  public sender: string
  public to: array<string>
  public subject: string
  public text: string = ""
  public html: string = ""
  public cc: array<string> = []
  public bcc: array<string> = []
  public reply_to: string = ""
end

--" Where a mail goes. --"
trait Mailer
  --" Sends the mail. `true` when the service took it. --"
  fun send(self, mail: Mail) -> Result<bool, Error>
end

type Transport = fun(Request) -> Result<Response, Error>

fun mail_error<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
end

fun clean(text: string) -> bool
  not text.contains("\n") and not text.contains("\r") and not text.contains("\0")
end

fun address_ok(a: string) -> bool
  clean(a) and a.trim() != "" and a.contains("@")
end

--" Why the mail cannot be sent, or `none`. --"
fun check(mail: Mail) -> string?
  if not address_ok(mail.sender) then
    return "the sender is not an address"
  end
  if mail.to.is_empty() then
    return "the mail has no recipient"
  end
  for a in mail.to.concat(mail.cc).concat(mail.bcc) do
    if not address_ok(a) then
      return "`{a.replace("\n", " ").replace("\r", " ")}` is not an address"
    end
  end
  if mail.reply_to != "" and not address_ok(mail.reply_to) then
    return "the reply-to is not an address"
  end
  if not clean(mail.subject) then
    return "the subject holds a line break"
  end
  if mail.text == "" and mail.html == "" then
    return "the mail has no body"
  end
  none
end

fun reply_of(r: Result<Response, Error>) -> Result<bool, Error>
  if r.is_err() then
    return Result<bool, Error>.Err(r.unwrap_err())
  end
  let res = r.unwrap()
  if res.status >= 200 and res.status < 300 then
    return Result<bool, Error>.Ok(true)
  end
  mail_error<bool>("the mail service answered {res.status}: {res.body}")
end

fun json_headers(extra: map<string, string>) -> map<string, string>
  let h: map<string, string> = {"Content-Type": "application/json", "Accept": "application/json"}
  for k in extra.keys() do
    h[k] = extra[k] ?? ""
  end
  h
end

fun strings(list: array<string>) -> Json
  Json.array(list.map(fun(s: string) -> Json Json.string(s) end))
end

--" Keeps the mails in memory: for tests. --"
struct MemoryMailer
  public sent: array<Mail>
end

impl MemoryMailer
  public fun new() -> MemoryMailer
    MemoryMailer { sent: [] }
  end
end

impl Mailer for MemoryMailer
  public fun send(self, mail: Mail) -> Result<bool, Error>
    let why = check(mail)
    if why != none then
      return mail_error<bool>(why)
    end
    self.sent.push(mail)
    Result<bool, Error>.Ok(true)
  end
end

--" Writes the mails in the log instead of sending them: for development. --"
struct LogMailer
end

impl Mailer for LogMailer
  public fun send(self, mail: Mail) -> Result<bool, Error>
    let why = check(mail)
    if why != none then
      return mail_error<bool>(why)
    end
    Log.info("mail to {mail.to.join(", ")}: {mail.subject}")
    Result<bool, Error>.Ok(true)
  end
end

--" [Resend](https://resend.com). --"
struct ResendMailer
  public key: string
  public base: string = "https://api.resend.com"
  public transport: Transport
end

impl ResendMailer
  public fun new(key: string) -> ResendMailer
    ResendMailer { key: key, base: "https://api.resend.com", transport: fun(r: Request) -> Result<Response, Error> http.send(r) end }
  end
end

impl Mailer for ResendMailer
  public fun send(self, mail: Mail) -> Result<bool, Error>
    let why = check(mail)
    if why != none then
      return mail_error<bool>(why)
    end
    let body: map<string, Json> = {"from": Json.string(mail.sender), "to": strings(mail.to), "subject": Json.string(mail.subject)}
    if mail.text != "" then
      body["text"] = Json.string(mail.text)
    end
    if mail.html != "" then
      body["html"] = Json.string(mail.html)
    end
    if not mail.cc.is_empty() then
      body["cc"] = strings(mail.cc)
    end
    if not mail.bcc.is_empty() then
      body["bcc"] = strings(mail.bcc)
    end
    if mail.reply_to != "" then
      body["reply_to"] = Json.string(mail.reply_to)
    end
    reply_of(self.transport(Request { method: "POST", url: "{self.base}/emails", headers: json_headers({"Authorization": "Bearer {self.key}"}), body: Json.object(body).to_text() }))
  end
end

--" [Postmark](https://postmarkapp.com). --"
struct PostmarkMailer
  public token: string
  public base: string = "https://api.postmarkapp.com"
  public transport: Transport
end

impl PostmarkMailer
  public fun new(token: string) -> PostmarkMailer
    PostmarkMailer { token: token, base: "https://api.postmarkapp.com", transport: fun(r: Request) -> Result<Response, Error> http.send(r) end }
  end
end

impl Mailer for PostmarkMailer
  public fun send(self, mail: Mail) -> Result<bool, Error>
    let why = check(mail)
    if why != none then
      return mail_error<bool>(why)
    end
    let body: map<string, Json> = {"From": Json.string(mail.sender), "To": Json.string(mail.to.join(",")), "Subject": Json.string(mail.subject)}
    if mail.text != "" then
      body["TextBody"] = Json.string(mail.text)
    end
    if mail.html != "" then
      body["HtmlBody"] = Json.string(mail.html)
    end
    if not mail.cc.is_empty() then
      body["Cc"] = Json.string(mail.cc.join(","))
    end
    if not mail.bcc.is_empty() then
      body["Bcc"] = Json.string(mail.bcc.join(","))
    end
    if mail.reply_to != "" then
      body["ReplyTo"] = Json.string(mail.reply_to)
    end
    reply_of(self.transport(Request { method: "POST", url: "{self.base}/email", headers: json_headers({"X-Postmark-Server-Token": self.token}), body: Json.object(body).to_text() }))
  end
end

fun person(address: string) -> Json
  -- `Name <a@b>` or `a@b`
  let open = address.index_of("<")
  if open != none and address.ends_with(">") then
    let name = address.substring(0, open).trim()
    let mail = address.substring(open + 1, address.len() - 1).trim()
    if name == "" then
      return Json.object({"email": Json.string(mail)})
    end
    return Json.object({"email": Json.string(mail), "name": Json.string(name)})
  end
  Json.object({"email": Json.string(address.trim())})
end

--" [SendGrid](https://sendgrid.com). --"
struct SendgridMailer
  public key: string
  public base: string = "https://api.sendgrid.com"
  public transport: Transport
end

impl SendgridMailer
  public fun new(key: string) -> SendgridMailer
    SendgridMailer { key: key, base: "https://api.sendgrid.com", transport: fun(r: Request) -> Result<Response, Error> http.send(r) end }
  end
end

impl Mailer for SendgridMailer
  public fun send(self, mail: Mail) -> Result<bool, Error>
    let why = check(mail)
    if why != none then
      return mail_error<bool>(why)
    end
    let to = Json.array(mail.to.map(fun(a: string) -> Json person(a) end))
    let personalization: map<string, Json> = {"to": to}
    if not mail.cc.is_empty() then
      personalization["cc"] = Json.array(mail.cc.map(fun(a: string) -> Json person(a) end))
    end
    if not mail.bcc.is_empty() then
      personalization["bcc"] = Json.array(mail.bcc.map(fun(a: string) -> Json person(a) end))
    end
    let content: array<Json> = []
    if mail.text != "" then
      content.push(Json.object({"type": Json.string("text/plain"), "value": Json.string(mail.text)}))
    end
    if mail.html != "" then
      content.push(Json.object({"type": Json.string("text/html"), "value": Json.string(mail.html)}))
    end
    let body: map<string, Json> = {"personalizations": Json.array([Json.object(personalization)]), "from": person(mail.sender), "subject": Json.string(mail.subject), "content": Json.array(content)}
    if mail.reply_to != "" then
      body["reply_to"] = person(mail.reply_to)
    end
    reply_of(self.transport(Request { method: "POST", url: "{self.base}/v3/mail/send", headers: json_headers({"Authorization": "Bearer {self.key}"}), body: Json.object(body).to_text() }))
  end
end

fun form(fields: array<(string, string)>) -> string
  fields.map(fun(f: (string, string)) -> string "{Url.encode(f.0)}={Url.encode(f.1)}" end).join("&")
end

--" [Mailgun](https://www.mailgun.com); `base` is `https://api.eu.mailgun.net` for the European region. --"
struct MailgunMailer
  public key: string
  public domain: string
  public base: string = "https://api.mailgun.net"
  public transport: Transport
end

impl MailgunMailer
  public fun new(key: string, domain: string) -> MailgunMailer
    MailgunMailer { key: key, domain: domain, base: "https://api.mailgun.net", transport: fun(r: Request) -> Result<Response, Error> http.send(r) end }
  end
end

impl Mailer for MailgunMailer
  public fun send(self, mail: Mail) -> Result<bool, Error>
    let why = check(mail)
    if why != none then
      return mail_error<bool>(why)
    end
    let fields: array<(string, string)> = [("from", mail.sender), ("subject", mail.subject)]
    for a in mail.to do
      fields.push(("to", a))
    end
    for a in mail.cc do
      fields.push(("cc", a))
    end
    for a in mail.bcc do
      fields.push(("bcc", a))
    end
    if mail.text != "" then
      fields.push(("text", mail.text))
    end
    if mail.html != "" then
      fields.push(("html", mail.html))
    end
    if mail.reply_to != "" then
      fields.push(("h:Reply-To", mail.reply_to))
    end
    let auth = Base64.encode("api:{self.key}")
    reply_of(self.transport(Request { method: "POST", url: "{self.base}/v3/{Url.encode(self.domain)}/messages", headers: {"Authorization": "Basic {auth}", "Content-Type": "application/x-www-form-urlencoded"}, body: form(fields) }))
  end
end

--" A job that sends a mail: `queue.push(SendMail { mail: m })`, with `handle_sends(queue, mailer)` in the worker. --"
struct SendMail
  public mail: Mail
end

--" Teaches `queue` to do the `SendMail` jobs with `mailer` (a refused mail is tried again like any job). --"
fun handle_sends(queue: qq.Queue, mailer: Mailer)
  queue.handle<SendMail>(fun(job: SendMail) -> string?
    let sent = mailer.send(job.mail)
    if sent.is_err() then sent.unwrap_err().message else none end
  end)
end

export SendMail, handle_sends, Mail, Mailer, Transport, MemoryMailer, LogMailer, ResendMailer, PostmarkMailer, SendgridMailer, MailgunMailer, check

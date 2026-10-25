import "mail.q" as m
import "queue.q" as qq

fun sample() -> m.Mail
  m.Mail { sender: "Blog <blog@example.org>", to: ["ada@example.org", "Bob <bob@example.org>"], subject: "Welcome", text: "Hello", html: "<p>Hello</p>", cc: ["cc@example.org"], reply_to: "help@example.org" }
end

--" A transport that keeps the requests and answers with `status`. --"
fun spy(seen: array<Request>, status: int) -> m.Transport
  fun(r: Request) -> Result<Response, Error>
    seen.push(r)
    Result<Response, Error>.Ok(Response { status: status, body: "{status}" })
  end
end

fun test_resend_gets_a_json_body_with_a_bearer_key()
  let seen: array<Request> = []
  let mailer = m.ResendMailer.new("key1")
  mailer.transport = spy(seen, 200)
  assert_eq(mailer.send(sample()).unwrap(), true)
  assert_eq(seen[0].url, "https://api.resend.com/emails")
  assert_eq(seen[0].headers["Authorization"], "Bearer key1")
  let body = Json.parse(seen[0].body ?? "").unwrap()
  assert_eq((body.get("subject") ?? Json.null()).as_string(), "Welcome")
  assert_eq((body.get("to") ?? Json.null()).as_array().len(), 2)
  assert_eq((body.get("reply_to") ?? Json.null()).as_string(), "help@example.org")
end

fun test_postmark_sendgrid_and_mailgun_use_their_own_shapes()
  let seen: array<Request> = []
  let pm = m.PostmarkMailer.new("tok")
  pm.transport = spy(seen, 200)
  pm.send(sample()).unwrap()
  assert_eq(seen[0].headers["X-Postmark-Server-Token"], "tok")
  assert_eq((Json.parse(seen[0].body ?? "").unwrap().get("To") ?? Json.null()).as_string(), "ada@example.org,Bob <bob@example.org>")

  let sg = m.SendgridMailer.new("k")
  sg.transport = spy(seen, 202)
  sg.send(sample()).unwrap()
  assert_eq(seen[1].url, "https://api.sendgrid.com/v3/mail/send")
  let p = (Json.parse(seen[1].body ?? "").unwrap().get("personalizations") ?? Json.null()).at(0) ?? Json.null()
  assert_eq((((p.get("to") ?? Json.null()).at(1) ?? Json.null()).get("name") ?? Json.null()).as_string(), "Bob")

  let mg = m.MailgunMailer.new("secret", "mg.example.org")
  mg.transport = spy(seen, 200)
  mg.send(sample()).unwrap()
  assert_eq(seen[2].url, "https://api.mailgun.net/v3/mg.example.org/messages")
  assert_eq(seen[2].headers["Authorization"], "Basic " + Base64.encode("api:secret"))
  assert((seen[2].body ?? "").contains("to=ada%40example.org&to=Bob%20%3Cbob%40example.org%3E"))
end

fun test_a_refused_mail_is_an_error_with_the_answer_of_the_service()
  let seen: array<Request> = []
  let mailer = m.ResendMailer.new("k")
  mailer.transport = spy(seen, 422)
  let r = mailer.send(sample())
  assert(r.unwrap_err().message.contains("422"))
end

fun test_header_injection_and_empty_mails_are_refused_before_any_request()
  let seen: array<Request> = []
  let mailer = m.ResendMailer.new("k")
  mailer.transport = spy(seen, 200)
  let bad = sample()
  bad.subject = "Hi\nBcc: evil@example.org"
  assert(mailer.send(bad).is_err())
  let bad_to = sample()
  bad_to.to = ["ada@example.org\r\nBcc: evil@example.org"]
  assert(mailer.send(bad_to).is_err())
  let none_to = sample()
  none_to.to = []
  assert(mailer.send(none_to).is_err())
  let empty = sample()
  empty.text = ""
  empty.html = ""
  assert(mailer.send(empty).is_err())
  assert_eq(seen.len(), 0)
end

fun test_the_memory_mailer_keeps_what_was_sent_and_a_queue_job_sends_it()
  let memory = m.MemoryMailer.new()
  let queue = qq.Queue.new(Db.connect("sqlite://:memory:").unwrap(), "sqlite")
  queue.install().unwrap()
  m.handle_sends(queue, memory)
  queue.push(m.SendMail { mail: sample() }).unwrap()
  queue.work(true).unwrap()
  assert_eq(memory.sent.len(), 1)
  assert_eq(memory.sent[0].subject, "Welcome")
end

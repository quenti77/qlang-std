import "notify.q" as nt
import "mail.q" as mail

fun note() -> nt.Notification
  nt.Notification { kind: "invoice", title: "Invoice paid", body: "Thank you", url: "https://x.org/i/1" }
end

fun test_one_notification_goes_to_every_channel_and_a_failure_does_not_stop_the_others()
  let memory = mail.MemoryMailer.new()
  let notifier = nt.Notifier.new()
  notifier.channel("mail", nt.MailChannel { mailer: memory, sender: "App <app@example.org>" })
  let inbox = nt.InboxChannel.new(Db.connect("sqlite://:memory:").unwrap(), "sqlite")
  inbox.install().unwrap()
  notifier.channel("inbox", inbox)
  let seen: array<Request> = []
  let hook = nt.WebhookChannel.slack("https://hooks.example.org/x")
  hook.transport = fun(r: Request) -> Result<Response, Error>
    seen.push(r)
    Result<Response, Error>.Ok(Response { status: 500, body: "" })
  end
  notifier.channel("slack", hook)

  let failures = notifier.send(["slack", "mail", "inbox", "sms"], "7", note())
  assert_eq(failures.len(), 3)
  -- the mail address "7" is not one: only the inbox worked
  assert(failures[0].starts_with("slack: the webhook answered 500"))
  assert(failures[2].starts_with("sms:"))
  assert_eq(inbox.unread_count("7").unwrap(), 1)
  assert_eq((Json.parse(seen[0].body ?? "").unwrap().get("text") ?? Json.null()).as_string(), "Invoice paid\nThank you\nhttps://x.org/i/1")
  assert_eq(notifier.send(["mail"], "ada@example.org", note()).len(), 0)
  assert(memory.sent[0].text.contains("https://x.org/i/1"))
end

fun test_the_inbox_lists_newest_first_and_a_user_reads_only_their_own()
  let inbox = nt.InboxChannel.new(Db.connect("sqlite://:memory:").unwrap(), "sqlite")
  inbox.install().unwrap()
  inbox.deliver("1", nt.Notification { kind: "a", title: "first" }).unwrap()
  inbox.deliver("1", nt.Notification { kind: "b", title: "second" }).unwrap()
  inbox.deliver("2", nt.Notification { kind: "c", title: "other" }).unwrap()
  let mine = inbox.list("1", 10).unwrap()
  assert_eq(mine.map(fun(i: nt.InboxItem) -> string i.title end), ["second", "first"])
  assert_eq(inbox.mark_read("2", mine[0].id).unwrap(), false)
  assert_eq(inbox.mark_read("1", mine[0].id).unwrap(), true)
  assert_eq(inbox.unread_count("1").unwrap(), 1)
  assert_eq(inbox.mark_all_read("1").unwrap(), 1)
  assert_eq(inbox.unread_count("1").unwrap(), 0)
  assert_eq(inbox.unread_count("2").unwrap(), 1)
end

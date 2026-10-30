import "accounts.q" as acc
import "app.q" as web
import "session.q" as sess
import "testing.q" as testing
import "../mail.q" as mail

struct World
  public app: web.App
  public accounts: acc.Accounts
  public mailer: mail.MemoryMailer
  public clock: array<int>
end

fun world(options: acc.Options) -> World
  let db = Db.connect("sqlite://:memory:").unwrap()
  let mailer = mail.MemoryMailer.new()
  let accounts = acc.Accounts.new(db, "sqlite", mailer, options)
  accounts.install().unwrap()
  let clock = [1000000]
  accounts.now = fun() -> int clock[0] end
  let app = web.App.new([])
  app.use(sess.sessions("test secret test secret test secret"))
  acc.mount(app, accounts, "/auth")
  let login = acc.require_login(accounts)
  let verified = acc.require_verified(accounts)
  -- a guard runs inside the request, where the session middleware has read the cookie
  app.get("/private", fun(req: Request) -> Response
    let refused = login(req)
    if refused != none then
      return refused
    end
    Response.text("secret")
  end)
  app.get("/verified", fun(req: Request) -> Response
    let refused = verified(req)
    if refused != none then
      return refused
    end
    Response.text("secret")
  end)
  World { app: app, accounts: accounts, mailer: mailer, clock: clock }
end

fun credentials(email: string, password: string) -> map<string, string>
  {"email": email, "password": password}
end

-- the token written in the last email
fun token_in(m: mail.Mail) -> string
  let at = assert_some(m.text.index_of("token="))
  let rest = m.text.substring(at + 6, m.text.len())
  let cut = rest.index_of("\n") ?? rest.len()
  rest.substring(0, cut)
end

fun test_registering_makes_an_account_and_sends_the_verification_email()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  let r = client.post_json("/auth/register", credentials("Ada@Example.org ", "correct horse"))
  r.expect_status(201)
  r.expect_body_contains("ada@example.org")
  r.expect_body_contains("\"verified\":false")
  assert(not r.body.contains("password"))
  assert_eq(w.mailer.sent.len(), 1)
  assert_eq(w.mailer.sent[0].to, ["ada@example.org"])
  assert(w.mailer.sent[0].text.contains("/email/verify?token="))
end

fun test_a_bad_address_a_short_password_and_a_taken_address_are_refused()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  client.post_json("/auth/register", credentials("not an email", "correct horse")).expect_status(422)
  client.post_json("/auth/register", credentials("a@b.org", "short")).expect_status(422)
  client.post_json("/auth/register", credentials("a@b.org", "x".repeat(2000))).expect_status(422)
  client.post_json("/auth/register", credentials("a@b.org", "correct horse")).expect_status(201)
  client.post_json("/auth/register", credentials("A@B.org", "another horse")).expect_status(409)
end

fun test_signing_in_out_and_the_guard()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  client.post_json("/auth/register", credentials("ada@example.org", "correct horse")).expect_status(201)
  client.get("/auth/me").expect_status(401)
  client.post_json("/auth/login", credentials("ada@example.org", "wrong horse")).expect_status(401)
  client.get("/auth/me").expect_status(401)
  let ok = client.post_json("/auth/login", credentials("ada@example.org", "correct horse"))
  ok.expect_status(200)
  client.get("/auth/me").expect_body_contains("ada@example.org")
  client.post("/auth/logout", "").expect_status(200)
  client.get("/auth/me").expect_status(401)
end

fun test_a_wrong_email_and_a_wrong_password_answer_the_same()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  client.post_json("/auth/register", credentials("ada@example.org", "correct horse")).expect_status(201)
  let unknown = client.post_json("/auth/login", credentials("nobody@example.org", "correct horse"))
  let wrong = client.post_json("/auth/login", credentials("ada@example.org", "wrong horse"))
  assert_eq(unknown.status, wrong.status)
  assert_eq(unknown.body, wrong.body)
end

fun test_the_session_identifier_changes_when_signing_in()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  client.post_json("/auth/register", credentials("ada@example.org", "correct horse")).expect_status(201)
  let before = client.get("/auth/me")
  let seen = client.cookies["qs"] ?? ""
  client.post_json("/auth/login", credentials("ada@example.org", "correct horse")).expect_status(200)
  assert(client.cookies["qs"] != seen)
end

fun test_the_email_check_works_once_and_only_in_time()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  client.post_json("/auth/register", credentials("ada@example.org", "correct horse")).expect_status(201)
  let token = token_in(w.mailer.sent[0])
  client.post_json("/auth/email/verify", {"token": "wrong"}).expect_status(400)
  let ok = client.get("/auth/email/verify?token={token}")
  ok.expect_status(200)
  ok.expect_body_contains("\"verified\":true")
  client.post_json("/auth/email/verify", {"token": token}).expect_status(400)
  -- an old link
  client.post_json("/auth/register", credentials("bob@example.org", "correct horse")).expect_status(201)
  let old = token_in(w.mailer.sent[1])
  w.clock[0] += 2 * 86400 * 1000
  client.post_json("/auth/email/verify", {"token": old}).expect_status(400)
end

fun test_signing_in_can_wait_for_the_email_check()
  let w = world(acc.Options { require_verified: true })
  let client = testing.Client.new(w.app)
  client.post_json("/auth/register", credentials("ada@example.org", "correct horse")).expect_status(201)
  client.post_json("/auth/login", credentials("ada@example.org", "correct horse")).expect_status(403)
  client.post_json("/auth/email/verify", {"token": token_in(w.mailer.sent[0])}).expect_status(200)
  client.post_json("/auth/login", credentials("ada@example.org", "correct horse")).expect_status(200)
end

fun test_the_guards_need_a_session_and_a_checked_address()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  client.get("/private").expect_status(401)
  client.post_json("/auth/register", credentials("ada@example.org", "correct horse")).expect_status(201)
  client.get("/private").expect_status(401)
  client.post_json("/auth/login", credentials("ada@example.org", "correct horse")).expect_status(200)
  client.get("/private").expect_status(200)
  client.get("/verified").expect_status(403)
  client.post_json("/auth/email/verify", {"token": token_in(w.mailer.sent[0])}).expect_status(200)
  client.get("/verified").expect_status(200)
  client.post("/auth/logout", "").expect_status(200)
  client.get("/verified").expect_status(401)
end

fun test_a_forgotten_password_is_reset_with_the_link_of_the_email()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  client.post_json("/auth/register", credentials("ada@example.org", "correct horse")).expect_status(201)
  let sent_before = w.mailer.sent.len()
  -- the same answer for an address that has no account, and no email
  let unknown = client.post_json("/auth/password/forgot", {"email": "nobody@example.org"})
  let known = client.post_json("/auth/password/forgot", {"email": "ada@example.org"})
  assert_eq(unknown.status, 202)
  assert_eq(unknown.body, known.body)
  assert_eq(w.mailer.sent.len(), sent_before + 1)
  let token = token_in(w.mailer.sent[sent_before])
  client.post_json("/auth/password/reset", {"token": token, "password": "short"}).expect_status(422)
  client.post_json("/auth/password/reset", {"token": "wrong", "password": "a brand new horse"}).expect_status(400)
  client.post_json("/auth/password/reset", {"token": token, "password": "a brand new horse"}).expect_status(200)
  -- the link works once
  client.post_json("/auth/password/reset", {"token": token, "password": "yet another horse"}).expect_status(400)
  client.post_json("/auth/login", credentials("ada@example.org", "correct horse")).expect_status(401)
  client.post_json("/auth/login", credentials("ada@example.org", "a brand new horse")).expect_status(200)
end

fun test_a_new_reset_link_ends_the_older_ones_and_old_links_expire()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  client.post_json("/auth/register", credentials("ada@example.org", "correct horse")).expect_status(201)
  client.post_json("/auth/password/forgot", {"email": "ada@example.org"})
  client.post_json("/auth/password/forgot", {"email": "ada@example.org"})
  let first = token_in(w.mailer.sent[1])
  let second = token_in(w.mailer.sent[2])
  client.post_json("/auth/password/reset", {"token": second, "password": "a brand new horse"}).expect_status(200)
  client.post_json("/auth/password/reset", {"token": first, "password": "yet another horse"}).expect_status(400)
  client.post_json("/auth/password/forgot", {"email": "ada@example.org"})
  let late = token_in(w.mailer.sent[3])
  w.clock[0] += 2 * 3600 * 1000
  client.post_json("/auth/password/reset", {"token": late, "password": "yet another horse"}).expect_status(400)
end

fun test_the_database_only_keeps_the_hash_of_a_token()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  client.post_json("/auth/register", credentials("ada@example.org", "correct horse")).expect_status(201)
  let token = token_in(w.mailer.sent[0])
  let rows = w.accounts.db.query("SELECT token_hash FROM accounts_tokens", []).unwrap()
  assert_eq(rows.len(), 1)
  assert(rows[0].get("token_hash", Json.null()).as_string() != token)
  let stored = w.accounts.db.query("SELECT password_hash FROM accounts", []).unwrap()
  assert(stored[0].get("password_hash", Json.null()).as_string().starts_with("$argon2"))
end

fun test_a_form_body_works_like_json_and_resending_is_for_the_signed_in()
  let w = world(acc.Options {})
  let client = testing.Client.new(w.app)
  client.post_form("/auth/register", credentials("ada@example.org", "correct horse")).expect_status(201)
  client.post("/auth/email/resend", "").expect_status(401)
  client.post_form("/auth/login", credentials("ada@example.org", "correct horse")).expect_status(200)
  client.post("/auth/email/resend", "").expect_status(202)
  assert_eq(w.mailer.sent.len(), 2)
end

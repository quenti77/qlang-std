import "app.q" as web
import "locale.q" as locale
import "testing.q" as testing
import "test_locale_routes.q" as routes
import "../i18n.q" as i18n

fun build() -> web.App
  let tr = i18n.Translator.new("en")
  tr.add("en", "welcome", "Hello \{name\}")
  tr.add("fr", "welcome", "Bonjour \{name\}")
  let app = web.App.new([])
  locale.use_locale(app, tr, ["en", "fr"])
  app.controllers(Reflect.callables(routes))
  app
end

fun test_the_accept_language_header_picks_the_language()
  let client = testing.Client.new(build())
  assert_eq(client.get("/hello").body, "Hello Ada")
  client.header("Accept-Language", "fr-FR,fr;q=0.9")
  let r = client.get("/hello")
  assert_eq(r.body, "Bonjour Ada")
  assert_eq(r.header("content-language"), "fr")
end

fun test_the_query_wins_and_is_remembered_in_a_cookie()
  let client = testing.Client.new(build())
  client.header("Accept-Language", "en")
  assert_eq(client.get("/hello?lang=fr").body, "Bonjour Ada")
  assert_eq(client.get("/hello").body, "Bonjour Ada")
  assert_eq(client.get("/hello?lang=xx").body, "Bonjour Ada")
  client.forget_cookies()
  assert_eq(client.get("/hello").body, "Hello Ada")
end

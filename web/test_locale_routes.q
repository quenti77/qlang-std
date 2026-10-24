-- A route for the tests of `locale.q`.
import "app.q" as web
import "../i18n.q" as i18n

#[web.Get("/hello")]
fun hello(lang: i18n.Lang) -> string
  lang.t("welcome", {"name": "Ada"})
end

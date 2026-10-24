--" # The language of a request

Chooses a language for each request and gives it to the handlers, with the messages of an
`i18n.Translator`.

```
let tr = Translator.new("en")
tr.load("fr", "lang/fr.json").unwrap()
tr.load("en", "lang/en.json").unwrap()

use_locale(app, tr, ["en", "fr"])      -- the translator, the `Lang` service and the middleware

#[web.Get("/hello")]
fun hello(lang: Lang) -> string
  lang.t("welcome", { "name": "Ada" })
end
```

The language is, in this order: `?lang=fr` (then remembered in the cookie `lang`), the cookie `lang`,
the `Accept-Language` header, the default language of the translator. The answer carries
`Content-Language`. A handler can also read `locale_of(req)`.
--"
import "../i18n.q" as i18n
import "app.q" as web
import "container.q" as di

--" The language chosen for this request (the default one without the middleware). --"
fun locale_of(req: Request) -> string
  let a = req.attrs["locale"]
  if a == none then
    return "en"
  end
  a.as<string>() ?? "en"
end

--" Chooses the language of each request among `available` (see above). --"
fun locale_middleware(tr: i18n.Translator, available: array<string>) -> web.Middleware
  fun(req: Request, next: web.Handler) -> Response
    let asked = req.query["lang"]
    let remembered = false
    let chosen = tr.default_locale
    if asked != none and available.contains(asked) then
      chosen = asked
      remembered = true
    else
      let saved = req.cookies["lang"]
      if saved != none and available.contains(saved) then
        chosen = saved
      else
        chosen = tr.negotiate(req.header("accept-language"), available)
      end
    end
    req.attrs["locale"] = Any.of(chosen)
    let res = next(req)
    res.headers["Content-Language"] = chosen
    if remembered then
      res.cookies.push(Cookie { name: "lang", value: chosen, max_age: 31536000, http_only: false })
    end
    res
  end
end

--" A provider for `Lang` handler parameters: add it with `Reflect.callable(locale, "lang_for")`. --"
#[di.Scoped]
fun lang_for(req: Request, tr: i18n.Translator) -> i18n.Lang
  tr.lang(locale_of(req))
end

--" Sets everything up: the translator and the `Lang` service in the container, and the middleware. --"
fun use_locale(app: web.App, tr: i18n.Translator, available: array<string>)
  app.container.set(tr)
  let provider = Reflect.callable("lang_for")
  if provider != none then
    app.container.provide(provider)
  end
  app.use(locale_middleware(tr, available))
end

export locale_of, locale_middleware, lang_for, use_locale

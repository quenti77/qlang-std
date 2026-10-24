--" # Translations

Messages by language, with placeholders and plural forms, and the choice of the language of a
request.

```
-- lang/fr.json
{ "welcome": "Bonjour {name}",
  "cart": { "items": { "one": "{count} article", "other": "{count} articles" } } }

let tr = Translator.new("en")
tr.load("fr", "lang/fr.json").unwrap()
tr.load("en", "lang/en.json").unwrap()

tr.t("fr", "welcome", { "name": "Ada" })      -- Bonjour Ada
tr.tn("fr", "cart.items", 3, {})              -- 3 articles
tr.t("fr-CA", "welcome", { "name": "Ada" })   -- fr-CA falls back to fr
tr.t("de", "welcome", { "name": "Ada" })      -- no German: the default language (en)
tr.t("en", "nope", {})                        -- nope: the key itself, so a hole is visible
```

A message file is a JSON object. Nested objects make dotted keys (`cart.items`). An object whose
keys are all plural categories (`zero`, `one`, `two`, `few`, `many`, `other`) is a message with
plural forms, chosen by `tn` with the rule of the language (`one` for 1 in English; `one` for 0 and 1 in
French; `one`, `few`, `many` in Russian and Polish...). `{count}` is filled in by `tn`.

Placeholders are written `{name}` and replaced by the value given for it; one that is not given is
left as it is. When a language lacks a key, the less specific one is tried (`fr-CA` then `fr`), then
the default language, then the key.
--"

--" Messages by language. --"
struct Translator
  public default_locale: string
  public messages: map<string, map<string, string>>
  public rules: map<string, fun(int) -> string>
end

--" A language chosen once, to translate without repeating it. --"
struct Lang
  public locale: string
  public translator: Translator
end

impl Lang
  public fun t(self, key: string, params: map<string, string>) -> string
    self.translator.t(self.locale, key, params)
  end

  public fun tn(self, key: string, count: int, params: map<string, string>) -> string
    self.translator.tn(self.locale, key, count, params)
  end

  public fun number(self, value: float, decimals: int) -> string
    self.translator.number(self.locale, value, decimals)
  end
end

fun categories() -> array<string>
  ["zero", "one", "two", "few", "many", "other"]
end

--" The language part of a tag: `fr` for `fr-CA` and `fr_CA`. --"
fun language_of(locale: string) -> string
  let cut = locale.replace("_", "-").split("-")
  cut[0].lower()
end

--" The built-in plural rule of a language. --"
fun plural_rule(language: string, n: int) -> string
  let m10 = n mod 10
  let m100 = n mod 100
  if ["ja", "zh", "ko", "vi", "id", "th", "ms"].contains(language) then
    return "other"
  end
  if language == "fr" or language == "pt" then
    return if n == 0 or n == 1 then "one" else "other" end
  end
  if ["ru", "uk", "be"].contains(language) then
    if m10 == 1 and m100 != 11 then
      return "one"
    end
    if m10 >= 2 and m10 <= 4 and not (m100 >= 12 and m100 <= 14) then
      return "few"
    end
    return "many"
  end
  if language == "pl" then
    if n == 1 then
      return "one"
    end
    if m10 >= 2 and m10 <= 4 and not (m100 >= 12 and m100 <= 14) then
      return "few"
    end
    return "many"
  end
  if language == "cs" or language == "sk" then
    if n == 1 then
      return "one"
    end
    if n >= 2 and n <= 4 then
      return "few"
    end
    return "other"
  end
  if language == "ar" then
    if n == 0 then
      return "zero"
    end
    if n == 1 then
      return "one"
    end
    if n == 2 then
      return "two"
    end
    if m100 >= 3 and m100 <= 10 then
      return "few"
    end
    if m100 >= 11 then
      return "many"
    end
    return "other"
  end
  if n == 1 then "one" else "other" end
end

fun fill(message: string, params: map<string, string>) -> string
  let out = message
  for name in params.keys() do
    out = out.replace("\{{name}\}", params[name] ?? "")
  end
  out
end

impl Translator
  --" A translator whose fallback language is `default_locale`. --"
  public fun new(default_locale: string) -> Translator
    Translator { default_locale: default_locale, messages: {}, rules: {} }
  end

  --" Sets (or replaces) one message. For plural forms, add `key#one`, `key#other`... --"
  public fun add(self, locale: string, key: string, message: string)
    let found = self.messages[locale]
    if found == none then
      self.messages[locale] = {key: message}
    else
      found[key] = message
    end
  end

  --" Uses another plural rule for a language (`one`, `few`, `many`, `other`...). --"
  public fun plural_rule(self, language: string, rule: fun(int) -> string)
    self.rules[language] = rule
  end

  --" Adds the messages of a JSON text. `err` when it is not an object of messages. --"
  public fun add_json(self, locale: string, text: string) -> Result<int, Error>
    let parsed = Json.parse(text)
    if parsed.is_err() then
      return Result<int, Error>.Err(parsed.unwrap_err())
    end
    let tree = parsed.unwrap()
    if not tree.is_object() then
      return Result<int, Error>.Err(Error { message: "{locale}: the messages must be a JSON object" })
    end
    Result<int, Error>.Ok(self.walk(locale, "", tree))
  end

  --" Reads the messages of `locale` from a JSON file. --"
  public fun load(self, locale: string, path: string) -> Result<int, Error>
    let text = fs.read(path)
    if text.is_err() then
      return Result<int, Error>.Err(text.unwrap_err())
    end
    self.add_json(locale, text.unwrap())
  end

  fun walk(self, locale: string, prefix: string, tree: Json) -> int
    let count = 0
    let keys = tree.as_object().keys()
    let plural = keys.len() > 0 and keys.filter(fun(k: string) -> bool not categories().contains(k) end).len() == 0
    for k in keys do
      let child = tree.get(k) ?? Json.null()
      if plural then
        if child.is_string() then
          self.add(locale, "{prefix}#{k}", child.as_string())
          count += 1
        end
        continue
      end
      let key = if prefix == "" then k else "{prefix}.{k}" end
      if child.is_string() then
        self.add(locale, key, child.as_string())
        count += 1
      else
        if child.is_object() then
          count += self.walk(locale, key, child)
        end
      end
    end
    count
  end

  --" The locales tried for `locale`, most specific first, ending with the default. --"
  public fun chain(self, locale: string) -> array<string>
    let out: array<string> = []
    let tag = locale.replace("_", "-")
    out.push(tag)
    let lang = language_of(tag)
    if lang != tag then
      out.push(lang)
    end
    if not out.contains(self.default_locale) then
      out.push(self.default_locale)
    end
    out
  end

  fun lookup(self, locale: string, key: string) -> string?
    for l in self.chain(locale) do
      let found = self.messages[l]
      if found != none then
        let m = found[key]
        if m != none then
          return m
        end
      end
    end
    none
  end

  --" Whether a message exists for `key` in `locale` or a fallback. --"
  public fun has(self, locale: string, key: string) -> bool
    self.lookup(locale, key) != none or self.lookup(locale, "{key}#other") != none
  end

  --" The message, with `{name}` placeholders filled from `params`; the key when there is none. --"
  public fun t(self, locale: string, key: string, params: map<string, string>) -> string
    let m = self.lookup(locale, key)
    if m == none then
      return key
    end
    fill(m, params)
  end

  --" The message for `count`, in the plural form of the language. `{count}` is filled in too. --"
  public fun tn(self, locale: string, key: string, count: int, params: map<string, string>) -> string
    let lang = language_of(locale)
    let rule = self.rules[lang]
    let category = if rule == none then plural_rule(lang, count) else rule(count) end
    let m = self.lookup(locale, "{key}#{category}") ?? self.lookup(locale, "{key}#other") ?? self.lookup(locale, key)
    if m == none then
      return key
    end
    let all: map<string, string> = {"count": "{count}"}
    for name in params.keys() do
      all[name] = params[name] ?? ""
    end
    fill(m, all)
  end

  --" A number written as the language does: `1 234,50` in French, `1,234.50` in English,
  `1.234,50` in German and Spanish. --"
  public fun number(self, locale: string, value: float, decimals: int) -> string
    let lang = language_of(locale)
    let group = ","
    let point = "."
    if ["fr", "ru", "uk", "cs", "sk", "pl", "sv", "nb", "fi"].contains(lang) then
      group = " "
      point = ","
    end
    if ["de", "es", "it", "nl", "pt", "id", "tr", "da"].contains(lang) then
      group = "."
      point = ","
    end
    let negative = value < 0.0
    let magnitude = if negative then -value else value end
    let scale = 10 ** decimals
    let scaled = (magnitude * (scale as float) + 0.5) as int
    let whole = scaled div scale
    let fraction = scaled mod scale
    let digits = "{whole}"
    let grouped = ""
    let i = digits.len()
    while i > 3 do
      grouped = group + digits.substring(i - 3, i) + grouped
      i -= 3
    end
    grouped = digits.substring(0, i) + grouped
    if decimals > 0 then
      grouped = grouped + point + "{fraction}".pad_left(decimals, "0")
    end
    if negative then "-{grouped}" else grouped end
  end

  --" The keys the default language has and `locale` lacks: what is left to translate. --"
  public fun missing(self, locale: string) -> array<string>
    let out: array<string> = []
    let base = self.messages[self.default_locale]
    if base == none then
      return out
    end
    let mine = self.messages[locale]
    for key in base.keys() do
      if mine == none or mine[key] == none then
        out.push(key)
      end
    end
    out
  end

  --" The language of a request: the best of `available` that `accept_language` (the header
  `Accept-Language`) asks for, by quality, or the default language. --"
  public fun negotiate(self, accept_language: string?, available: array<string>) -> string
    if accept_language == none then
      return self.default_locale
    end
    let best = self.default_locale
    let best_q = -1.0
    for part in accept_language.split(",") do
      let pieces = part.trim().split(";")
      let tag = pieces[0].trim()
      let q = 1.0
      if pieces.len() > 1 then
        let given = pieces[1].trim()
        if given.starts_with("q=") then
          q = float.parse(given.substring(2, given.len())) ?? 0.0
        end
      end
      if tag == "" or tag == "*" or q <= 0.0 or q <= best_q then
        continue
      end
      let chosen = self.pick(tag, available)
      if chosen != none then
        best = chosen
        best_q = q
      end
    end
    best
  end

  fun pick(self, tag: string, available: array<string>) -> string?
    let wanted = tag.replace("_", "-").lower()
    for a in available do
      if a.lower() == wanted then
        return a
      end
    end
    let lang = language_of(wanted)
    for a in available do
      if a.lower() == lang then
        return a
      end
    end
    for a in available do
      if language_of(a) == lang then
        return a
      end
    end
    none
  end

  --" The language `locale` as a `Lang`, to translate without repeating it. --"
  public fun lang(self, locale: string) -> Lang
    Lang { locale: locale, translator: self }
  end

  --" The locales that have messages. --"
  public fun locales(self) -> array<string>
    self.messages.keys()
  end
end

export Translator, Lang, plural_rule, language_of

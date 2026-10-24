import "i18n.q" as i18n

const FR = "\{\"welcome\": \"Bonjour \{name\}\", \"cart\": \{\"items\": \{\"one\": \"\{count\} article\", \"other\": \"\{count\} articles\"\}\}, \"only_fr\": \"seulement\"\}"
const EN = "\{\"welcome\": \"Hello \{name\}\", \"cart\": \{\"items\": \{\"one\": \"\{count\} item\", \"other\": \"\{count\} items\"\}\}, \"bye\": \"Bye\"\}"

fun build() -> i18n.Translator
  let tr = i18n.Translator.new("en")
  assert_eq(tr.add_json("fr", FR).unwrap(), 4)
  tr.add_json("en", EN).unwrap()
  tr
end

fun test_messages_have_placeholders()
  let tr = build()
  assert_eq(tr.t("fr", "welcome", {"name": "Ada"}), "Bonjour Ada")
  assert_eq(tr.t("en", "welcome", {"name": "Ada"}), "Hello Ada")
  assert_eq(tr.t("en", "welcome", {}), "Hello \{name\}")
end

fun test_a_missing_message_falls_back_then_shows_the_key()
  let tr = build()
  assert_eq(tr.t("fr-CA", "welcome", {"name": "Zoe"}), "Bonjour Zoe")
  assert_eq(tr.t("fr", "bye", {}), "Bye")
  assert_eq(tr.t("de", "welcome", {"name": "Zoe"}), "Hello Zoe")
  assert_eq(tr.t("en", "nope", {}), "nope")
  assert(tr.has("fr", "cart.items"))
  assert_eq(tr.has("fr", "nope"), false)
end

fun test_plural_forms_follow_the_rule_of_the_language()
  let tr = build()
  assert_eq(tr.tn("en", "cart.items", 1, {}), "1 item")
  assert_eq(tr.tn("en", "cart.items", 0, {}), "0 items")
  assert_eq(tr.tn("fr", "cart.items", 0, {}), "0 article")
  assert_eq(tr.tn("fr", "cart.items", 2, {}), "2 articles")
end

fun test_builtin_rules_for_slavic_and_arabic()
  assert_eq(i18n.plural_rule("ru", 1), "one")
  assert_eq(i18n.plural_rule("ru", 3), "few")
  assert_eq(i18n.plural_rule("ru", 11), "many")
  assert_eq(i18n.plural_rule("ru", 21), "one")
  assert_eq(i18n.plural_rule("pl", 22), "few")
  assert_eq(i18n.plural_rule("ar", 2), "two")
  assert_eq(i18n.plural_rule("ja", 1), "other")
end

fun test_your_own_rule_wins()
  let tr = build()
  tr.plural_rule("en", fun(n: int) -> string if n == 0 then "other" else "one" end end)
  assert_eq(tr.tn("en", "cart.items", 5, {}), "5 item")
end

fun test_the_language_of_a_request()
  let tr = build()
  let available = ["en", "fr"]
  assert_eq(tr.negotiate("fr-CA,fr;q=0.9,en;q=0.8", available), "fr")
  assert_eq(tr.negotiate("de,en;q=0.7", available), "en")
  assert_eq(tr.negotiate("de", available), "en")
  assert_eq(tr.negotiate(none, available), "en")
  assert_eq(tr.negotiate("en;q=0.5,fr;q=0.9", available), "fr")
end

fun test_numbers_are_written_as_the_language_does()
  let tr = build()
  assert_eq(tr.number("en", 1234567.891, 2), "1,234,567.89")
  assert_eq(tr.number("de", 1234.5, 2), "1.234,50")
  assert_eq(tr.number("fr", -1234.5, 1), "-1 234,5")
  assert_eq(tr.number("en", 12.0, 0), "12")
end

fun test_a_lang_remembers_its_locale_and_missing_keys_are_listed()
  let tr = build()
  let fr = tr.lang("fr")
  assert_eq(fr.t("welcome", {"name": "Ada"}), "Bonjour Ada")
  assert_eq(fr.tn("cart.items", 3, {}), "3 articles")
  assert_eq(tr.missing("fr"), ["bye"])
  assert_eq(tr.missing("en").len(), 0)
  assert_eq(tr.add_json("de", "[1]").is_err(), true)
end

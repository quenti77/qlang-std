--" # Validation by annotations

Rules are annotations on the fields of a structure; `check` reads them and says what is wrong.

```
struct NewUser
  #[NotBlank, Length(2, 40)]
  public name: string
  #[Email]
  public email: string
  #[Min(18), Max(130)]
  public age: int
  #[Valid]
  public address: Address
end

let errors = Validator.new().check(Any.of(input))   -- array<FieldError>, empty when all is well
```

A rule is skipped for a field that is `none` (add `#[Required]` to forbid it). `#[Valid]` checks the
structure (or each structure of the array) a field holds, with the field's name in front of the
inner names (`address.city`). Your own rules: `validator.rule("Slug", fun(a: AnnotationInfo, v: Any) -> string? ... end)`
gives the message when `v` is wrong, or `none`.
--"

--" The field must have a value (not `none`) and, for a text, not be empty or only spaces. --"
#[annotation]
struct NotBlank
end

--" The field must not be `none`. --"
#[annotation]
struct Required
end

--" The smallest number allowed. --"
#[annotation]
struct Min
  value: float
end

--" The biggest number allowed. --"
#[annotation]
struct Max
  value: float
end

--" The number of characters of a text, or of elements of an array: at least `min`, at most
`max` (`-1`: no limit). --"
#[annotation]
struct Length
  min: int = 0
  max: int = -1
end

--" The text must look like an email address (`name@domain.tld`). --"
#[annotation]
struct Email
end

--" The text must match this regular expression (the whole text). --"
#[annotation]
struct Pattern
  regex: string
  message: string = ""
end

--" The value must be one of these (compared as text). --"
#[annotation]
struct OneOf
  values: array<string>
end

--" Check the structure, or each structure of the array, that the field holds. --"
#[annotation]
struct Valid
end

--" One thing wrong: the field (`address.city`, `tags[2]`) and what is wrong with it. --"
struct FieldError
  public field: string
  public message: string
end

--" Checks values against the rules written on their fields. --"
struct Validator
  custom: map<string, fun(AnnotationInfo, Any) -> string?>
end

fun joined(prefix: string, name: string) -> string
  if prefix == "" then name else "{prefix}.{name}" end
end

fun number_of(v: Any) -> float?
  let i = v.as<int>()
  if i != none then
    return i as float
  end
  v.as<float>()
end

fun length_of(v: Any) -> int?
  let s = v.as<string>()
  if s != none then
    return s.len()
  end
  let items = Reflect.items(v)
  if items != none then
    return items.len()
  end
  none
end

fun is_none_value(v: Any) -> bool
  Json.of(v).is_null()
end

impl Validator
  --" A validator with the built-in rules. --"
  public fun new() -> Validator
    Validator { custom: {} }
  end

  --" Adds a rule called like an annotation of yours (`#[Slug]`). `check` gives the message
  that says what is wrong with the value, or `none` if it is fine. --"
  public fun rule(self, name: string, check: fun(AnnotationInfo, Any) -> string?)
    self.custom[name] = check
  end

  --" Everything wrong with `value`, a structure held by an `Any`. --"
  public fun check(self, value: Any) -> array<FieldError>
    let out: array<FieldError> = []
    self.check_into(value, "", out)
    out
  end

  --" Whether `value` has no error. --"
  public fun is_valid(self, value: Any) -> bool
    self.check(value).is_empty()
  end

  fun check_into(self, value: Any, prefix: string, out: array<FieldError>)
    let info = Reflect.info_of(value)
    if info == none then
      return
    end
    for field in info.fields do
      if field.annotations.is_empty() then
        continue
      end
      let inner = Reflect.get(value, field.name)
      if inner == none then
        continue
      end
      let name = joined(prefix, field.name)
      for a in field.annotations do
        self.apply(a, inner, name, out)
      end
    end
  end

  fun apply(self, a: AnnotationInfo, v: Any, name: string, out: array<FieldError>)
    let fail = fun(message: string)
      out.push(FieldError { field: name, message: message })
    end
    if a.name == "Required" then
      if is_none_value(v) then
        fail("is required")
      end
      return
    end
    if a.name == "NotBlank" then
      let text = v.as<string>()
      if is_none_value(v) or (text != none and text.trim().is_empty()) then
        fail("must not be blank")
      end
      return
    end
    -- the other rules leave an absent value alone
    if is_none_value(v) then
      return
    end
    if a.name == "Valid" then
      let items = Reflect.items(v)
      if items != none then
        let i = 0
        for item in items do
          self.check_into(item, "{name}[{i}]", out)
          i += 1
        end
      else
        self.check_into(v, name, out)
      end
      return
    end
    if a.name == "Min" or a.name == "Max" then
      let n = number_of(v)
      let limit = a.get_float("value")
      if n == none or limit == none then
        return
      end
      if a.name == "Min" and n < limit then
        fail("must be at least {limit}")
      end
      if a.name == "Max" and n > limit then
        fail("must be at most {limit}")
      end
      return
    end
    if a.name == "Length" then
      let size = length_of(v)
      let low = a.get_int("min")
      let high = a.get_int("max")
      if size == none then
        return
      end
      if low != none and size < low then
        fail("must have at least {low} characters or elements")
      end
      if high != none and high >= 0 and size > high then
        fail("must have at most {high} characters or elements")
      end
      return
    end
    if a.name == "Email" then
      let text = v.as<string>()
      if text != none and not regex.matches(text, "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$") then
        fail("is not a valid email address")
      end
      return
    end
    if a.name == "Pattern" then
      let text = v.as<string>()
      let pattern = a.get_string("regex")
      if text != none and pattern != none and not regex.matches(text, "^(?:" + pattern + ")$") then
        let own = a.get_string("message")
        if own != none and own != "" then
          fail(own)
        else
          fail("does not match the expected format")
        end
      end
      return
    end
    if a.name == "OneOf" then
      let allowed = a.args["values"]
      if allowed == none then
        return
      end
      let shown = Json.of(v).to_text()
      let text = v.as<string>()
      let n = number_of(v)
      let mine = shown
      if text != none then
        mine = text
      else
        if n != none then
          mine = "{n}"
        end
      end

      let names: array<string> = []
      let found = false
      for j in allowed.as_array() do
        let option = j.as_string()
        names.push(option)
        if option == mine then
          found = true
        end
      end
      if not found then
        let list = names.join(", ")
        fail("must be one of {list}")
      end
      return
    end
    let own = self.custom[a.name]
    if own != none then
      let message = own(a, v)
      if message != none then
        fail(message)
      end
    end
  end
end

export Validator, FieldError, NotBlank, Required, Min, Max, Length, Email, Pattern, OneOf, Valid

import "validate.q" as v
import NotBlank, Required, Min, Max, Length, Email, Pattern, OneOf, Valid from "validate.q"

struct Address
  #[NotBlank]
  public city: string
  #[Pattern("[0-9]\{5}", message: "must be five digits")]
  public zip: string
end

struct NewUser
  #[NotBlank, Length(2, 10)]
  public name: string
  #[Email]
  public email: string
  #[Min(18), Max(130)]
  public age: int
  #[OneOf(["admin", "member"])]
  public role: string
  #[Valid]
  public address: Address
  #[Valid, Length(0, 2)]
  public others: array<Address>
  #[Required]
  public nick: string?
  public free: string
end

fun good() -> NewUser
  NewUser {
    name: "Ada",
    email: "ada@example.org",
    age: 36,
    role: "admin",
    address: Address { city: "Lyon", zip: "69001" },
    others: [],
    nick: "ada",
    free: "anything",
  }
end

fun fields(errors: array<v.FieldError>) -> array<string>
  errors.map(fun(e: v.FieldError) -> string "{e.field}: {e.message}" end)
end

fun test_a_good_value_has_no_error()
  let validator = v.Validator.new()
  assert(validator.is_valid(Any.of(good())))
  assert_eq(validator.check(Any.of(good())).len(), 0)
end

fun test_each_rule_says_what_is_wrong()
  let u = good()
  u.name = " "
  u.email = "nope"
  u.age = 12
  u.role = "root"
  u.nick = none
  let errors = fields(v.Validator.new().check(Any.of(u)))
  assert(errors.contains("name: must not be blank"))
  assert(errors.contains("email: is not a valid email address"))
  assert(errors.contains("age: must be at least 18.0"))
  assert(errors.contains("role: must be one of admin, member"))
  assert(errors.contains("nick: is required"))
  assert(errors.contains("name: must have at least 2 characters or elements"))
  assert_eq(errors.len(), 6)
end

fun test_lengths_and_maximums()
  let u = good()
  u.name = "A very long name"
  u.age = 200
  let errors = fields(v.Validator.new().check(Any.of(u)))
  assert(errors.contains("name: must have at most 10 characters or elements"))
  assert(errors.contains("age: must be at most 130.0"))
end

fun test_nested_structures_are_named_by_their_path()
  let u = good()
  u.address = Address { city: "", zip: "12" }
  u.others = [Address { city: "Paris", zip: "75001" }, Address { city: "x", zip: "bad" }, Address { city: "y", zip: "75002" }]
  let errors = fields(v.Validator.new().check(Any.of(u)))
  assert(errors.contains("address.city: must not be blank"))
  assert(errors.contains("address.zip: must be five digits"))
  assert(errors.contains("others[1].zip: must be five digits"))
  assert(errors.contains("others: must have at most 2 characters or elements"))
end

fun test_an_absent_value_is_left_alone_unless_it_is_required()
  let u = good()
  u.nick = none
  let errors = fields(v.Validator.new().check(Any.of(u)))
  assert_eq(errors, ["nick: is required"])
end

fun test_your_own_rules_are_called_by_the_name_of_their_annotation()
  let validator = v.Validator.new()
  validator.rule("Even", fun(a: AnnotationInfo, value: Any) -> string?
    let n = value.as<int>()
    if n != none and n mod 2 != 0 then "must be even" else none end
  end)
  assert(validator.check(Any.of(Pair { n: 3 })).len() == 1)
  assert(validator.check(Any.of(Pair { n: 4 })).len() == 0)
  -- without the rule, the annotation is ignored
  assert(v.Validator.new().check(Any.of(Pair { n: 3 })).len() == 0)
end

#[annotation]
struct Even
end

struct Pair
  #[Even]
  public n: int
end

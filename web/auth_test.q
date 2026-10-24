import "app.q" as web
import "auth.q" as auth
import "cache.q" as cc
import "testing.q" as testing
import "../jwt.q" as jwt
import "test_auth_routes.q" as routes

const SECRET = "a-long-enough-secret-a-long-enough-secret"

struct Session
  public sub: string
  public exp: int
  public scope: string = ""
end

fun build() -> web.App
  let app = web.App.new([])
  let keys = [jwt.Key.hs256(SECRET)]
  app.guard("jwt", auth.jwt_guard(keys, jwt.Options { now: 1000, issuer: "https://api.example" }))
  app.guard("admin", auth.scope_guard(["admin"]))
  app.controllers(Reflect.callables(routes))
  app
end

fun token(sub: string, exp: int, scope: string) -> string
  jwt.sign_json(Json.object({"sub": Json.string(sub), "exp": Json.number(exp as float), "iss": Json.string("https://api.example"), "scope": Json.string(scope)}), jwt.Key.hs256(SECRET)).unwrap()
end

fun test_a_route_without_a_valid_token_is_a_401_with_a_challenge()
  let client = testing.Client.new(build())
  let none_given = client.get("/me")
  none_given.expect_status(401)
  assert_eq(none_given.header("www-authenticate"), "Bearer")
  client.bearer("garbage")
  let bad = client.get("/me").expect_status(401)
  assert((bad.header("www-authenticate") ?? "").contains("invalid_token"))
  assert(not bad.body.contains("garbage"))
  let expired = testing.Client.new(build())
  expired.bearer(token("1", 500, ""))
  expired.get("/me").expect_status(401)
end

fun test_a_valid_token_gives_its_claims_to_the_route()
  let client = testing.Client.new(build())
  client.bearer(token("42", 2000, "read"))
  assert_eq(client.get("/me").expect_status(200).body, "42:2000")
end

fun test_a_scope_is_a_403_when_missing_and_passes_when_there()
  let client = testing.Client.new(build())
  client.bearer(token("1", 2000, "read write"))
  let refused = client.get("/admin").expect_status(403)
  assert((refused.header("www-authenticate") ?? "").contains("insufficient_scope"))
  let admin = testing.Client.new(build())
  admin.bearer(token("2", 2000, "read admin"))
  admin.get("/admin").expect_status(200)
  -- the scope guard alone, without a token first, is a 401
  assert_eq(testing.Client.new(build()).get("/admin").status, 401)
end

fun test_a_jwks_is_fetched_once_and_kept_in_the_cache()
  let cache = cc.Cache.memory()
  cache.put_text("jwks:https://id.example/keys", "\{\"keys\":[]\}", 60)
  assert_eq(auth.fetch_jwks("https://id.example/keys", cache, 60).unwrap().len(), 0)
end

-- Routes for the tests of `auth.q`.
import "app.q" as web
import "auth.q" as auth

struct Claims
  public sub: string
  public exp: int
end

#[web.Get("/me")]
#[web.Guard("jwt")]
fun me(req: Request) -> string
  let c = auth.claims_of<Claims>(req)
  if c == none then
    return "?"
  end
  "{c.sub}:{c.exp}"
end

#[web.Get("/admin")]
#[web.Guard("jwt")]
#[web.Guard("admin")]
fun admin() -> string
  "welcome"
end

#[web.Get("/admin-only")]
#[web.Guard("admin")]
fun only_admin() -> string
  "x"
end

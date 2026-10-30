--" # Policies: who can do what to what

A **policy** answers "can this user do this to that?" with rules you write once, so that the controllers
and the templates ask the same question instead of repeating the test. Guards say who may reach a
route; a policy says what they may do with a given item (their own post, an unpublished page...).

```
let posts = Policy<User, Post>.create()
posts.before(fun(user: User, ability: string) -> bool? if user.admin then true else none end end)
posts.allow("update", fun(user: User, post: Post) -> bool post.author_id == user.id end)
posts.allow("view", fun(user: User, post: Post) -> bool post.published or post.author_id == user.id end)

posts.can(user, "update", post)                  -- bool
posts.authorize(user, "update", post)            -- Result<bool, web.Problem>: Err is a 403
posts.filter(user, "view", all_posts)            -- only the ones the user may view
```

An ability nobody defined is **refused** (closed by default). `before` runs first: `true` allows
everything for that user (an administrator), `false` refuses everything, `none` lets the rules decide.
--"
import "app.q" as web

--" The rules about one kind of item (`S`) for one kind of user (`U`). --"
struct Policy<U, S>
  rules: map<string, fun(U, S) -> bool>
  gate: fun(U, string) -> bool?
end

impl<U, S> Policy<U, S>
  --" A policy with no rule: everything is refused. --"
  public fun create() -> Policy<U, S>
    Policy<U, S> { rules: {}, gate: fun(user: U, ability: string) -> bool?
      none
    end }
  end

  --" The user may do `ability` to an item when `rule` says so. --"
  public fun allow(self, ability: string, rule: fun(U, S) -> bool) -> Policy<U, S>
    self.rules[ability] = rule
    self
  end

  --" A check that runs before the rules: `true` allows, `false` refuses, `none` goes on. --"
  public fun before(self, gate: fun(U, string) -> bool?) -> Policy<U, S>
    self.gate = gate
    self
  end

  --" Whether the user may do `ability` to `item`. --"
  public fun can(self, user: U, ability: string, item: S) -> bool
    let early = self.gate(user, ability)
    if early != none then
      return early == true
    end
    let rule = self.rules[ability]
    if rule == none then
      return false
    end
    rule(user, item)
  end

  public fun cannot(self, user: U, ability: string, item: S) -> bool
    not self.can(user, ability, item)
  end

  --" `Ok(true)`, or a `403` problem a handler can return as it is. --"
  public fun authorize(self, user: U, ability: string, item: S) -> Result<bool, web.Problem>
    if self.can(user, ability, item) then
      return Result<bool, web.Problem>.Ok(true)
    end
    Result<bool, web.Problem>.Err(web.Problem { status: 403, message: "Forbidden" })
  end

  --" The items the user may do `ability` to. --"
  public fun filter(self, user: U, ability: string, items: array<S>) -> array<S>
    let kept: array<S> = []
    for item in items do
      if self.can(user, ability, item) then
        kept.push(item)
      end
    end
    kept
  end
end

export Policy

import "policy.q" as p

struct User
  public id: int
  public admin: bool
end

struct Post
  public author_id: int
  public published: bool
end

fun posts() -> p.Policy<User, Post>
  let policy = p.Policy<User, Post>.create()
  policy.before(fun(user: User, ability: string) -> bool?
    if user.admin then true else none end
  end)
  policy.allow("update", fun(user: User, post: Post) -> bool post.author_id == user.id end)
  policy.allow("view", fun(user: User, post: Post) -> bool post.published or post.author_id == user.id end)
  policy
end

fun test_a_rule_decides_and_an_unknown_ability_is_refused()
  let policy = posts()
  let ada = User { id: 1, admin: false }
  assert(policy.can(ada, "update", Post { author_id: 1, published: false }))
  assert(policy.cannot(ada, "update", Post { author_id: 2, published: true }))
  assert(policy.cannot(ada, "delete", Post { author_id: 1, published: true }))
end

fun test_before_allows_an_administrator_everything()
  let policy = posts()
  assert(policy.can(User { id: 9, admin: true }, "delete", Post { author_id: 1, published: false }))
end

fun test_authorize_is_a_403_and_filter_keeps_the_allowed_ones()
  let policy = posts()
  let ada = User { id: 1, admin: false }
  let refused = policy.authorize(ada, "update", Post { author_id: 2, published: true })
  assert_eq(refused.unwrap_err().status, 403)
  assert(policy.authorize(ada, "view", Post { author_id: 2, published: true }).is_ok())
  let all = [Post { author_id: 1, published: false }, Post { author_id: 2, published: false }, Post { author_id: 3, published: true }]
  assert_eq(policy.filter(ada, "view", all).len(), 2)
end

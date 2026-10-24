import "refresh.q" as rf

fun fresh(clock: array<int>) -> rf.Refresh
  let r = rf.Refresh.new(Db.connect("sqlite://:memory:").unwrap())
  r.clock = fun() -> int clock[0] end
  r.install().unwrap()
  r
end

fun test_a_token_is_rotated_and_the_old_one_is_burnt()
  let clock = [1000000]
  let r = fresh(clock)
  let first = r.issue("42").unwrap()
  let second = r.rotate(first).unwrap()
  assert_eq(second.user, "42")
  assert(second.token != first)
  let third = r.rotate(second.token).unwrap()
  assert_eq(third.user, "42")
end

fun test_a_burnt_token_that_comes_back_closes_the_whole_session()
  let clock = [1000000]
  let r = fresh(clock)
  let first = r.issue("42").unwrap()
  let second = r.rotate(first).unwrap()
  let again = r.rotate(first)
  assert(again.unwrap_err().message.starts_with("reused"))
  -- the thief and the owner are both out
  assert(r.rotate(second.token).unwrap_err().message.starts_with("invalid"))
end

fun test_unknown_and_expired_tokens_are_refused()
  let clock = [1000000]
  let r = fresh(clock)
  assert(r.rotate("nope").unwrap_err().message.starts_with("invalid"))
  let t = r.issue("1").unwrap()
  clock[0] += (r.ttl + 1) * 1000
  assert(r.rotate(t).unwrap_err().message.starts_with("expired"))
  assert_eq(r.purge().unwrap(), 1)
end

fun test_revoke_ends_a_session_and_revoke_user_ends_all_of_them()
  let clock = [1000000]
  let r = fresh(clock)
  let a = r.issue("7").unwrap()
  let b = r.issue("7").unwrap()
  let other = r.issue("8").unwrap()
  assert(r.revoke(a).unwrap())
  assert(r.rotate(a).is_err())
  assert(r.rotate(b).is_ok())
  assert(not r.revoke("unknown").unwrap())
  assert(r.revoke_user("7").unwrap() >= 1)
  assert(r.rotate(other).is_ok())
end

fun test_the_database_holds_a_hash_not_the_token()
  let clock = [1000000]
  let r = fresh(clock)
  let t = r.issue("1").unwrap()
  let rows = r.db.query("SELECT token_hash FROM refresh_tokens", []).unwrap()
  assert(rows[0].get("token_hash", Json.null()).as_string() != t)
end

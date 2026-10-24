import "cache.q" as c

struct Post
  public id: int
  public title: string
end

fun test_a_value_comes_back_until_it_expires()
  let cache = c.Cache.memory()
  cache.put("n", 42, 60)
  assert_eq(cache.get<int>("n"), 42)
  assert_eq(cache.get<int>("other"), none)
  cache.put("short", "x", 1)
  time.sleep(1100)
  assert_eq(cache.get<string>("short"), none)
end

fun test_structs_go_through_json()
  let cache = c.Cache.memory()
  cache.put("p", Post { id: 1, title: "Hi" }, 60)
  let back = cache.get<Post>("p")
  assert_eq(back != none, true)
  assert_eq(cache.get<int>("p"), none)
end

fun test_remember_produces_once()
  let cache = c.Cache.memory()
  let calls = [0]
  let make = fun() -> int
    calls[0] += 1
    calls[0] * 10
  end
  assert_eq(cache.remember<int>("k", 60, make), 10)
  assert_eq(cache.remember<int>("k", 60, make), 10)
  assert_eq(calls[0], 1)
  cache.forget("k")
  assert_eq(cache.remember<int>("k", 60, make), 20)
end

fun test_scopes_keep_keys_apart()
  let cache = c.Cache.memory()
  let a = cache.scoped("a")
  let b = cache.scoped("b")
  a.put("k", 1, 60)
  assert_eq(b.get<int>("k"), none)
  assert_eq(a.get<int>("k"), 1)
  assert_eq(cache.get<int>("a:k"), 1)
end

fun test_files_keep_values_between_caches()
  let one = c.Cache.files(env.get("TMPDIR") ?? "/tmp")
  one.put("qlang-std-cache-test", "hello", 60)
  let two = c.Cache.files(env.get("TMPDIR") ?? "/tmp")
  assert_eq(two.get<string>("qlang-std-cache-test"), "hello")
  two.forget("qlang-std-cache-test")
  assert_eq(one.get<string>("qlang-std-cache-test"), none)
end

fun test_counters_add_one_and_expire()
  let cache = c.Cache.memory()
  assert_eq(cache.increment("hits", 60), 1)
  assert_eq(cache.increment("hits", 60), 2)
  assert_eq(cache.scoped("other").increment("hits", 60), 1)
end

--" Needs a server: QLANG_TEST_REDIS (see queue_redis_test.q). --"
fun test_redis_shares_values_and_counts_exactly()
  let url = env.get("QLANG_TEST_REDIS")
  if url == none then
    return
  end
  let r = Redis.connect(url).unwrap()
  r.command(["FLUSHDB"]).unwrap()
  let one = c.Cache.redis(r, "t:")
  let two = c.Cache.redis(Redis.connect(url).unwrap(), "t:")
  one.put("n", 42, 60)
  assert_eq(two.get<int>("n"), 42)
  assert_eq(two.remember<int>("k", 60, fun() -> int 7 end), 7)
  assert_eq(one.get<int>("k"), 7)
  one.forget("n")
  assert_eq(two.get<int>("n"), none)
  assert_eq(one.increment("hits", 60), 1)
  assert_eq(two.increment("hits", 60), 2)
  assert_eq(one.increment("hits", 60), 3)
end

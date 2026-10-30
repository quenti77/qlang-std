--" # Cache

Keeps the result of slow work for a while. A `Cache` stores texts under a key with a lifetime;
the typed helpers turn any value into JSON and back.

```
let cache = Cache.memory()
let top = cache.remember<array<Post>>("top-posts", 60, fun() -> array<Post> posts.top(10) end)
cache.put("answer", 42, 300)                    -- 300 seconds
let again = cache.get<int>("answer")            -- 42, or none once it expired
```

Where the texts live is a `Store`:

| Store | Shared by | Lives until |
| --- | --- | --- |
| `MemoryStore` (`Cache.memory()`) | the requests of one worker | the worker stops |
| `FileStore` (`Cache.files("/tmp/cache")`) | every worker of the machine | the lifetime ends (a file per key) |
| `RedisStore` (`Cache.redis(redis, "app:")`) | every worker of every machine | the lifetime ends (Redis expires the key) |
| `DbStore` (`Cache.database(db, "cache")`) | every worker of every machine using the database | the lifetime ends (a row per key; `prune()` removes the old ones) |

Each worker of `qlang serve` has its own memory, so a memory cache is a per-worker one: use a
`FileStore` when every worker of one machine must see the same value, a `RedisStore` when several
machines must. Write your own `Store` for a database, etc.
--"

--" Where a cache keeps its texts. `ttl` is in seconds; the store drops an entry once it is older. --"
trait Store
  fun read(self, key: string) -> string?
  fun write(self, key: string, value: string, ttl: int)
  fun drop(self, key: string)
  --" Adds 1 to a counter (0 if there is none) and gives the new value; a new counter lives `ttl`
  seconds. The step is done in one go where the store can (Redis), which is what makes a counter
  safe to share. --"
  fun incr(self, key: string, ttl: int) -> int
end

struct Entry
  public value: string
  public expires: int
end

--" A store in the memory of the worker. --"
struct MemoryStore
  entries: map<string, Entry>
end

impl MemoryStore
  public fun new() -> MemoryStore
    MemoryStore { entries: {} }
  end
end

impl Store for MemoryStore
  public fun read(self, key: string) -> string?
    let found = self.entries[key]
    if found == none then
      return none
    end
    if found.expires <= time.now() then
      self.entries.remove(key)
      return none
    end
    found.value
  end

  public fun write(self, key: string, value: string, ttl: int)
    self.entries[key] = Entry { value: value, expires: time.now() + ttl * 1000 }
  end

  public fun drop(self, key: string)
    self.entries.remove(key)
  end

  public fun incr(self, key: string, ttl: int) -> int
    let now = int.parse(self.read(key) ?? "0") ?? 0
    let found = self.entries[key]
    let until = if found == none then time.now() + ttl * 1000 else found.expires end
    self.entries[key] = Entry { value: "{now + 1}", expires: until }
    now + 1
  end
end

--" A store with a file per key in `dir`, which must exist. The first line of a file is the
moment (milliseconds) its entry expires. --"
struct FileStore
  dir: string
end

impl FileStore
  public fun new(dir: string) -> FileStore
    FileStore { dir: dir }
  end

  fun path_of(self, key: string) -> string
    "{self.dir}/{Hash.sha256(key)}.cache"
  end
end

impl Store for FileStore
  public fun read(self, key: string) -> string?
    let text = fs.read(self.path_of(key))
    if text.is_err() then
      return none
    end
    let whole = text.unwrap()
    let cut = whole.index_of("\n")
    if cut == none then
      return none
    end
    let until = int.parse(whole.substring(0, cut))
    if until == none or until <= time.now() then
      return none
    end
    whole.substring(cut + 1, whole.len())
  end

  public fun write(self, key: string, value: string, ttl: int)
    let until = time.now() + ttl * 1000
    fs.write(self.path_of(key), "{until}\n{value}")
  end

  public fun drop(self, key: string)
    fs.write(self.path_of(key), "0\n")
  end

  public fun incr(self, key: string, ttl: int) -> int
    let now = int.parse(self.read(key) ?? "0") ?? 0
    if now == 0 then
      self.write(key, "1", ttl)
    else
      -- keep the time the counter started with: the file holds it on its first line
      let text = fs.read(self.path_of(key))
      if text.is_ok() then
        let whole = text.unwrap()
        let cut = whole.index_of("\n") ?? 0
        fs.write(self.path_of(key), "{whole.substring(0, cut)}\n{now + 1}")
      end
    end
    now + 1
  end
end

--" A store in Redis, shared by every worker of every machine. `prefix` is put before each key. --"
struct RedisStore
  public redis: Redis
  public prefix: string
end

impl RedisStore
  public fun new(redis: Redis, prefix: string) -> RedisStore
    RedisStore { redis: redis, prefix: prefix }
  end
end

impl Store for RedisStore
  public fun read(self, key: string) -> string?
    let r = self.redis.get(self.prefix + key)
    if r.is_err() then
      Log.error("cache: {r.unwrap_err().message}")
      return none
    end
    r.unwrap()
  end

  public fun write(self, key: string, value: string, ttl: int)
    let r = self.redis.set_ex(self.prefix + key, value, if ttl < 1 then 1 else ttl end)
    if r.is_err() then
      Log.error("cache: {r.unwrap_err().message}")
    end
  end

  public fun drop(self, key: string)
    let r = self.redis.del(self.prefix + key)
    if r.is_err() then
      Log.error("cache: {r.unwrap_err().message}")
    end
  end

  public fun incr(self, key: string, ttl: int) -> int
    let r = self.redis.eval("local n = redis.call('INCR', KEYS[1]) if n == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end return n", [self.prefix + key], ["{ttl}"])
    if r.is_err() or not r.unwrap().is_number() then
      Log.error("cache: the counter could not be increased")
      return 0
    end
    r.unwrap().as_number() as int
  end
end

--" A store in a SQL database (SQLite, PostgreSQL, MySQL): one row per key in `table`, shared by
every worker of every machine that uses the database. Call `install()` once (a migration, or at start
up) to make the table. Writing replaces the row; a counter (`incr`) is read then written, so it is
not exact when two workers increase it at the same moment: use Redis for a limit that must be. --"
struct DbStore
  public db: Db
  public table: string
end

fun db_number(n: int) -> Json
  Json.number(n as float)
end

impl DbStore
  public fun new(db: Db, table: string) -> DbStore
    DbStore { db: db, table: table }
  end

  --" Makes the table if it does not exist. --"
  public fun install(self) -> Result<bool, Error>
    let made = self.db.execute("CREATE TABLE IF NOT EXISTS {self.table} (k VARCHAR(190) PRIMARY KEY, v TEXT NOT NULL, expires_at BIGINT NOT NULL)", [])
    if made.is_err() then
      return Result<bool, Error>.Err(made.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" Removes the rows that expired; how many. --"
  public fun prune(self) -> Result<int, Error>
    self.db.execute("DELETE FROM {self.table} WHERE expires_at <= ?", [db_number(time.now())])
  end
end

impl Store for DbStore
  public fun read(self, key: string) -> string?
    let rows = self.db.query("SELECT v FROM {self.table} WHERE k = ? AND expires_at > ?", [Json.string(key), db_number(time.now())])
    if rows.is_err() then
      Log.error("cache: {rows.unwrap_err().message}")
      return none
    end
    let found = rows.unwrap()
    if found.is_empty() then
      return none
    end
    found[0].get("v", Json.null()).as_string()
  end

  public fun write(self, key: string, value: string, ttl: int)
    let r = self.db.transaction(fun() -> Result<bool, Error>
      let gone = self.db.execute("DELETE FROM {self.table} WHERE k = ?", [Json.string(key)])
      if gone.is_err() then
        return Result<bool, Error>.Err(gone.unwrap_err())
      end
      let saved = self.db.execute("INSERT INTO {self.table} (k, v, expires_at) VALUES (?, ?, ?)", [Json.string(key), Json.string(value), db_number(time.now() + ttl * 1000)])
      if saved.is_err() then
        return Result<bool, Error>.Err(saved.unwrap_err())
      end
      Result<bool, Error>.Ok(true)
    end)
    if r.is_err() then
      Log.error("cache: {r.unwrap_err().message}")
    end
  end

  public fun drop(self, key: string)
    let r = self.db.execute("DELETE FROM {self.table} WHERE k = ?", [Json.string(key)])
    if r.is_err() then
      Log.error("cache: {r.unwrap_err().message}")
    end
  end

  public fun incr(self, key: string, ttl: int) -> int
    let n = (int.parse(self.read(key) ?? "0") ?? 0) + 1
    if n == 1 then
      self.write(key, "1", ttl)
    else
      let r = self.db.execute("UPDATE {self.table} SET v = ? WHERE k = ?", [Json.string("{n}"), Json.string(key)])
      if r.is_err() then
        Log.error("cache: {r.unwrap_err().message}")
      end
    end
    n
  end
end

--" A cache over a store. --"
struct Cache
  store: Store
  prefix: string
end

impl Cache
  public fun new(store: Store) -> Cache
    Cache { store: store, prefix: "" }
  end

  --" A cache in the memory of the worker. --"
  public fun memory() -> Cache
    Cache.new(MemoryStore.new())
  end

  --" A cache in Redis (shared by every worker of every machine); keys start with `prefix`. --"
  public fun redis(redis: Redis, prefix: string) -> Cache
    Cache.new(RedisStore.new(redis, prefix))
  end

  --" A cache in a SQL database, in `table` (made by `DbStore.new(db, table).install()`). --"
  public fun database(db: Db, table: string) -> Cache
    Cache.new(DbStore.new(db, table))
  end

  --" Adds 1 to a counter and gives the new value; a new counter lives `ttl` seconds. Atomic in
  Redis, so a limit shared by several workers stays exact. --"
  public fun increment(self, key: string, ttl: int) -> int
    self.store.incr(self.prefix + key, ttl)
  end

  --" A cache in files of `dir` (shared by the workers). --"
  public fun files(dir: string) -> Cache
    Cache.new(FileStore.new(dir))
  end

  --" The same store, with `name:` put before every key (one cache per feature). --"
  public fun scoped(self, name: string) -> Cache
    Cache { store: self.store, prefix: "{self.prefix}{name}:" }
  end

  --" The text under `key`, or `none` when there is none or it has expired. --"
  public fun get_text(self, key: string) -> string?
    self.store.read(self.prefix + key)
  end

  public fun put_text(self, key: string, value: string, ttl: int)
    self.store.write(self.prefix + key, value, ttl)
  end

  --" The value under `key` read as a `T`, or `none` (absent, expired, or not a `T`). --"
  public fun get<T>(self, key: string) -> T?
    let text = self.get_text(key)
    if text == none then
      return none
    end
    let parsed = Json.parse(text)
    if parsed.is_err() then
      return none
    end
    let value = Json.to<T>(parsed.unwrap())
    if value.is_err() then
      return none
    end
    value.unwrap()
  end

  --" Keeps `value` for `ttl` seconds. --"
  public fun put<T>(self, key: string, value: T, ttl: int)
    self.put_text(key, Json.of(value).to_text(), ttl)
  end

  --" Forgets `key`. --"
  public fun forget(self, key: string)
    self.store.drop(self.prefix + key)
  end

  public fun has(self, key: string) -> bool
    self.get_text(key) != none
  end

  --" The value under `key`; when there is none, `produce()` makes it and it is kept for `ttl`
  seconds. --"
  public fun remember<T>(self, key: string, ttl: int, produce: fun() -> T) -> T
    let found = self.get<T>(key)
    if found != none then
      return found
    end
    let made = produce()
    self.put<T>(key, made, ttl)
    made
  end
end

export Store, MemoryStore, FileStore, RedisStore, DbStore, Cache

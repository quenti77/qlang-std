--" # Refresh tokens

A JWT lives a few minutes; a *refresh token* lives days and buys a new JWT. It is a random text kept in
your database (as a hash, so a leaked table gives nothing), which you can revoke. This module issues
them and **rotates** them: each use gives a new token and burns the old one, and if a burnt token comes
back (it was stolen) the whole family is revoked.

```
let refresh = Refresh.new(db)
refresh.install().unwrap()
let first = refresh.issue("42").unwrap()             -- at login: send it to the client

let next = refresh.rotate(first)                     -- at /token/refresh
if next.is_ok() then
  let access = jwt.sign(Claims { sub: next.unwrap().user, exp: ... }, key).unwrap()
  -- send `access` and `next.unwrap().token`
end
```

`rotate` fails with a message that starts with `invalid`, `expired` or `reused`. `revoke_user` ends every
session of a user (a password change, a "sign out everywhere").
--"

--" A refresh token store in a SQL database. --"
struct Refresh
  public db: Db
  --" Seconds a token lives (30 days by default). --"
  public ttl: int = 2592000
  --" The table. --"
  public table: string = "refresh_tokens"
  --" The time in milliseconds; tests give their own. --"
  public clock: fun() -> int
end

--" The token to send, and the user it belongs to. --"
struct Rotated
  public user: string
  public token: string
end

fun refresh_error<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
end

fun digest(token: string) -> string
  Hash.sha256(token)
end

fun number(n: int) -> Json
  Json.number(n as float)
end

impl Refresh
  public fun new(db: Db) -> Refresh
    Refresh { db: db, ttl: 2592000, table: "refresh_tokens", clock: fun() -> int time.now() end }
  end

  --" Makes the table if it does not exist. --"
  public fun install(self) -> Result<bool, Error>
    let made = self.db.execute("CREATE TABLE IF NOT EXISTS {self.table} (token_hash VARCHAR(64) PRIMARY KEY, user_id VARCHAR(190) NOT NULL, family VARCHAR(64) NOT NULL, expires_at BIGINT NOT NULL, used_at BIGINT)", [])
    if made.is_err() then
      return Result<bool, Error>.Err(made.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  fun store(self, user: string, family: string) -> Result<string, Error>
    let random = Crypto.token(32)
    if random.is_err() then
      return Result<string, Error>.Err(random.unwrap_err())
    end
    let token = random.unwrap()
    let saved = self.db.execute("INSERT INTO {self.table} (token_hash, user_id, family, expires_at) VALUES (?, ?, ?, ?)", [Json.string(digest(token)), Json.string(user), Json.string(family), number(self.clock() + self.ttl * 1000)])
    if saved.is_err() then
      return Result<string, Error>.Err(saved.unwrap_err())
    end
    Result<string, Error>.Ok(token)
  end

  --" A new token for `user`, starting a new family (one login). --"
  public fun issue(self, user: string) -> Result<string, Error>
    let family = Crypto.token(12)
    if family.is_err() then
      return Result<string, Error>.Err(family.unwrap_err())
    end
    self.store(user, family.unwrap())
  end

  --" Burns `token` and gives its successor. If `token` was already used, every token of its family is
  revoked and the error starts with `reused`. --"
  public fun rotate(self, token: string) -> Result<Rotated, Error>
    let hash = digest(token)
    let rows = self.db.query("SELECT user_id, family, expires_at, used_at FROM {self.table} WHERE token_hash = ?", [Json.string(hash)])
    if rows.is_err() then
      return Result<Rotated, Error>.Err(rows.unwrap_err())
    end
    if rows.unwrap().is_empty() then
      return refresh_error<Rotated>("invalid: this refresh token is unknown")
    end
    let row = rows.unwrap()[0]
    let family = (row.get("family", Json.null())).as_string()
    let user = (row.get("user_id", Json.null())).as_string()
    let used = row.get("used_at", Json.null())
    if not used.is_null() then
      self.db.execute("DELETE FROM {self.table} WHERE family = ?", [Json.string(family)])
      return refresh_error<Rotated>("reused: this refresh token was already used; the session is closed")
    end
    if (row.get("expires_at", Json.null())).as_number() as int <= self.clock() then
      return refresh_error<Rotated>("expired: this refresh token has expired")
    end
    -- whoever marks it first wins: a second request with the same token is a reuse
    let burnt = self.db.execute("UPDATE {self.table} SET used_at = ? WHERE token_hash = ? AND used_at IS NULL", [number(self.clock()), Json.string(hash)])
    if burnt.is_err() then
      return Result<Rotated, Error>.Err(burnt.unwrap_err())
    end
    if burnt.unwrap() != 1 then
      self.db.execute("DELETE FROM {self.table} WHERE family = ?", [Json.string(family)])
      return refresh_error<Rotated>("reused: this refresh token was already used; the session is closed")
    end
    let next = self.store(user, family)
    if next.is_err() then
      return Result<Rotated, Error>.Err(next.unwrap_err())
    end
    Result<Rotated, Error>.Ok(Rotated { user: user, token: next.unwrap() })
  end

  --" Revokes this token's whole session (a "sign out"). `false` if the token is unknown. --"
  public fun revoke(self, token: string) -> Result<bool, Error>
    let rows = self.db.query("SELECT family FROM {self.table} WHERE token_hash = ?", [Json.string(digest(token))])
    if rows.is_err() then
      return Result<bool, Error>.Err(rows.unwrap_err())
    end
    if rows.unwrap().is_empty() then
      return Result<bool, Error>.Ok(false)
    end
    let gone = self.db.execute("DELETE FROM {self.table} WHERE family = ?", [rows.unwrap()[0].get("family", Json.null())])
    if gone.is_err() then
      return Result<bool, Error>.Err(gone.unwrap_err())
    end
    Result<bool, Error>.Ok(true)
  end

  --" Revokes every session of `user`. Gives how many tokens were deleted. --"
  public fun revoke_user(self, user: string) -> Result<int, Error>
    self.db.execute("DELETE FROM {self.table} WHERE user_id = ?", [Json.string(user)])
  end

  --" Deletes the tokens that have expired (run it now and then). --"
  public fun purge(self) -> Result<int, Error>
    self.db.execute("DELETE FROM {self.table} WHERE expires_at <= ?", [number(self.clock())])
  end
end

export Refresh, Rotated

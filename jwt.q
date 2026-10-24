--" # JSON Web Tokens (JWT)

A token that says who you are and until when, signed so that nobody can change it: `header.payload.signature`,
each part in URL-safe base64. A server hands one out after a login and checks it on each request, without
looking anything up.

```
let key = jwt.Key.hs256(secret)                                   -- a secret of 32 characters or more
let token = jwt.sign(Session { sub: "42", exp: now + 900, scope: "read write" }, key).unwrap()

let checked = jwt.verify(token, [key], jwt.Options.new())         -- Result<Token, Error>
let session = checked.unwrap().claims<Session>().unwrap()
```

| Key | For |
| --- | --- |
| `Key.hs256(secret)` | a secret that the issuer and the checker share (HMAC-SHA256) |
| `Key.rs256(pem)`, `rs384`, `rs512`, `es256`, `es384`, `eddsa` | a key pair: **sign** with the private key (PEM in PKCS#8, `BEGIN PRIVATE KEY`), **verify** with the public one (PEM or JWK). Needs the `qlang` command. |

Verifying checks, in this order: the shape; **the algorithm is one of your keys' algorithms** (never what the
token says it wants: `none` is refused, and a public key is never used as an HMAC secret); the signature, with the key
whose `kid` the header names; `exp` and `nbf` (with `leeway` seconds of grace); `iss` and `aud` when you ask for them.
A token without `exp` is refused unless you say `require_exp: false`. An error says which check failed (`error_kind`).

To check the tokens of an identity provider (Auth0, Keycloak, Google...), read its JWKS (`keys_from_jwks`, or
`fetch_jwks` in `web/auth.q`) and give the keys to `verify`: the `kid` of each token picks the right one.

A JWT is signed, not encrypted: anybody can read the payload. Put no secret in it, keep it short-lived (minutes)
and renew it with a refresh token that you keep in your database, where you can revoke it.
--"

--" A key, for signing or for checking. --"
struct Key
  --" `HS256`, `RS256`, `RS384`, `RS512`, `ES256`, `ES384` or `EdDSA`. --"
  public alg: string
  --" The secret, or a PEM, or a JWK (JSON text). --"
  public key: string
  --" The name that the token header carries, to tell the keys of a set apart. --"
  public kid: string? = none
end

impl Key
  public fun hs256(secret: string) -> Key
    Key { alg: "HS256", key: secret }
  end

  public fun rs256(pem: string) -> Key
    Key { alg: "RS256", key: pem }
  end

  public fun rs384(pem: string) -> Key
    Key { alg: "RS384", key: pem }
  end

  public fun rs512(pem: string) -> Key
    Key { alg: "RS512", key: pem }
  end

  public fun es256(pem: string) -> Key
    Key { alg: "ES256", key: pem }
  end

  public fun es384(pem: string) -> Key
    Key { alg: "ES384", key: pem }
  end

  public fun eddsa(pem: string) -> Key
    Key { alg: "EdDSA", key: pem }
  end

  --" The same key under a name (`kid`). --"
  public fun named(self, kid: string) -> Key
    Key { alg: self.alg, key: self.key, kid: kid }
  end
end

--" What to check besides the signature. --"
struct Options
  --" The `iss` the token must carry, or `none`. --"
  public issuer: string? = none
  --" The `aud` the token must carry (alone or in a list), or `none`. --"
  public audience: string? = none
  --" Seconds of difference between two clocks that are accepted for `exp` and `nbf`. --"
  public leeway: int = 0
  --" A token without `exp` is refused. --"
  public require_exp: bool = true
  --" The time in seconds; `0` is the clock (tests give theirs). --"
  public now: int = 0
end

impl Options
  public fun new() -> Options
    Options {}
  end
end

--" A token that passed every check. --"
struct Token
  public alg: string
  public header: Json
  public payload: Json
end

impl Token
  --" The claims read as a structure of yours (the fields you do not name are ignored). --"
  public fun claims<T>(self) -> Result<T, Error>
    Json.to<T>(self.payload)
  end

  --" A claim, or `none`. --"
  public fun get(self, name: string) -> Json?
    self.payload.get(name)
  end

  --" `sub`, or `none`. --"
  public fun subject(self) -> string?
    let s = self.payload.get("sub")
    if s != none and s.is_string() then s.as_string() else none end
  end

  --" The permissions of the token: the words of a `scope` text (`"read write"`), or the texts of an
  `scopes` or `permissions` list. --"
  public fun scopes(self) -> array<string>
    let out: array<string> = []
    let scope = self.payload.get("scope")
    if scope != none and scope.is_string() then
      for w in scope.as_string().split(" ") do
        if w != "" then
          out.push(w)
        end
      end
    end
    for name in ["scopes", "permissions"] do
      let list = self.payload.get(name)
      if list != none and list.is_array() then
        for x in list.as_array() do
          if x.is_string() then
            out.push(x.as_string())
          end
        end
      end
    end
    out
  end
end

fun fail<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
end

fun b64(text: string) -> string
  Base64.encode_url_bytes(text.to_bytes())
end

fun unb64(text: string) -> string?
  let b = Base64.decode_bytes(text)
  if b == none then none else b.to_string() end
end

fun signature_of(key: Key, input: string) -> Result<bytes, Error>
  if key.alg == "HS256" then
    if key.key.len() < 32 then
      return fail<bytes>("the HS256 secret must be at least 32 characters long")
    end
    return Result<bytes, Error>.Ok(Hash.hmac_sha256_raw(key.key.to_bytes(), input.to_bytes()))
  end
  Crypto.sign(key.alg, key.key, input.to_bytes())
end

--" Signs a payload (a `Json` object) and gives the token. --"
fun sign_json(payload: Json, key: Key) -> Result<string, Error>
  let header: map<string, Json> = {"alg": Json.string(key.alg), "typ": Json.string("JWT")}
  let kid = key.kid
  if kid != none then
    header["kid"] = Json.string(kid)
  end
  let input = b64(Json.object(header).to_text()) + "." + b64(payload.to_text())
  let sig = signature_of(key, input)
  if sig.is_err() then
    return Result<string, Error>.Err(sig.unwrap_err())
  end
  Result<string, Error>.Ok(input + "." + Base64.encode_url_bytes(sig.unwrap()))
end

--" Signs a structure (its public fields are the claims: `sub`, `exp`, `scope`...) and gives the token. --"
fun sign<T>(payload: T, key: Key) -> Result<string, Error>
  sign_json(Json.of(payload), key)
end

--" Why a check failed: `malformed`, `algorithm`, `key`, `signature`, `expired`, `not_yet_valid`, `claims`. --"
fun error_kind(e: Error) -> string
  let m = e.message
  for kind in ["malformed", "algorithm", "key", "signature", "expired", "not_yet_valid", "claims"] do
    if m.starts_with("{kind}:") then
      return kind
    end
  end
  "claims"
end

fun number_claim(payload: Json, name: string) -> int?
  let v = payload.get(name)
  if v != none and v.is_number() then v.as_number() as int else none end
end

fun audience_ok(payload: Json, wanted: string) -> bool
  let aud = payload.get("aud")
  if aud == none then
    return false
  end
  if aud.is_string() then
    return aud.as_string() == wanted
  end
  if aud.is_array() then
    for x in aud.as_array() do
      if x.is_string() and x.as_string() == wanted then
        return true
      end
    end
  end
  false
end

fun check_signature(key: Key, input: string, sig: bytes) -> bool
  if key.alg == "HS256" then
    let expected = signature_of(key, input)
    return expected.is_ok() and Crypto.equal_bytes(expected.unwrap(), sig)
  end
  let r = Crypto.verify(key.alg, key.key, input.to_bytes(), sig)
  r.is_ok() and r.unwrap()
end

--" Checks a token against the keys and the options, and gives what it says. --"
fun verify(token: string, keys: array<Key>, opts: Options) -> Result<Token, Error>
  let parts = token.split(".")
  if parts.len() != 3 or parts[0] == "" or parts[1] == "" then
    return fail<Token>("malformed: a token has three parts separated by dots")
  end
  let header_text = unb64(parts[0])
  let payload_text = unb64(parts[1])
  let sig = Base64.decode_bytes(parts[2])
  if header_text == none or payload_text == none or sig == none then
    return fail<Token>("malformed: the token is not URL-safe base64")
  end
  let header = Json.parse(header_text)
  let payload = Json.parse(payload_text)
  if header.is_err() or payload.is_err() or not header.unwrap().is_object() or not payload.unwrap().is_object() then
    return fail<Token>("malformed: the header and the payload must be JSON objects")
  end
  let h = header.unwrap()
  let alg_json = h.get("alg")
  if alg_json == none or not alg_json.is_string() then
    return fail<Token>("malformed: the header has no `alg`")
  end
  let alg = alg_json.as_string()
  let kid_json = h.get("kid")
  let kid = if kid_json != none and kid_json.is_string() then kid_json.as_string() else none end
  -- the algorithm comes from your keys, never from the token alone
  let candidates: array<Key> = []
  for k in keys do
    if k.alg == alg and (kid == none or k.kid == none or k.kid == kid) then
      candidates.push(k)
    end
  end
  if candidates.is_empty() then
    if keys.filter(fun(k: Key) -> bool k.alg == alg end).is_empty() then
      return fail<Token>("algorithm: the algorithm {alg} is not accepted here")
    end
    return fail<Token>("key: no key has the name {kid ?? "?"}")
  end
  let input = parts[0] + "." + parts[1]
  let ok = false
  for k in candidates do
    if check_signature(k, input, sig) then
      ok = true
      break
    end
  end
  if not ok then
    return fail<Token>("signature: the signature is not valid")
  end
  let p = payload.unwrap()
  let now = if opts.now > 0 then opts.now else time.now() div 1000 end
  let exp = number_claim(p, "exp")
  if exp == none and opts.require_exp then
    return fail<Token>("claims: the token has no `exp`")
  end
  if exp != none and now - opts.leeway >= exp then
    return fail<Token>("expired: the token expired")
  end
  let nbf = number_claim(p, "nbf")
  if nbf != none and now + opts.leeway < nbf then
    return fail<Token>("not_yet_valid: the token is not valid yet")
  end
  let issuer = opts.issuer
  if issuer != none then
    let iss = p.get("iss")
    if iss == none or not iss.is_string() or iss.as_string() != issuer then
      return fail<Token>("claims: the issuer is not {issuer}")
    end
  end
  let audience = opts.audience
  if audience != none and not audience_ok(p, audience) then
    return fail<Token>("claims: the audience is not {audience}")
  end
  Result<Token, Error>.Ok(Token { alg: alg, header: h, payload: p })
end

--" The keys of a JWKS document (`{"keys": [...]}`), as an identity provider publishes it. The algorithm is
the `alg` of each key, or `RS256`, `ES256`/`ES384`, `EdDSA` from its type. Keys that are not for signatures
are left out. --"
fun keys_from_jwks(text: string) -> Result<array<Key>, Error>
  let parsed = Json.parse(text)
  if parsed.is_err() then
    return Result<array<Key>, Error>.Err(parsed.unwrap_err())
  end
  let list = parsed.unwrap().get("keys")
  if list == none or not list.is_array() then
    return fail<array<Key>>("the JWKS has no `keys` list")
  end
  let out: array<Key> = []
  for jwk in list.as_array() do
    if not jwk.is_object() then
      continue
    end
    let use = jwk.get("use")
    if use != none and use.is_string() and use.as_string() != "sig" then
      continue
    end
    let kty = jwk.get("kty")
    if kty == none or not kty.is_string() then
      continue
    end
    let alg_json = jwk.get("alg")
    let alg = ""
    if alg_json != none and alg_json.is_string() then
      alg = alg_json.as_string()
    else
      if kty.as_string() == "RSA" then
        alg = "RS256"
      end
      if kty.as_string() == "OKP" then
        alg = "EdDSA"
      end
      if kty.as_string() == "EC" then
        let crv = jwk.get("crv")
        alg = if crv != none and crv.is_string() and crv.as_string() == "P-384" then "ES384" else "ES256" end
      end
    end
    if alg == "" or alg == "HS256" then
      continue
    end
    let kid_json = jwk.get("kid")
    let kid = if kid_json != none and kid_json.is_string() then kid_json.as_string() else none end
    out.push(Key { alg: alg, key: jwk.to_text(), kid: kid })
  end
  Result<array<Key>, Error>.Ok(out)
end

export Key, Options, Token, sign, sign_json, verify, error_kind, keys_from_jwks

-- Throwaway keys made for these tests with openssl (written without their armor in the source).
import "jwt.q" as jwt

struct Session
  public sub: string
  public exp: int
  public scope: string = ""
end

fun rsa_private() -> string
  "-----BEGIN PRIVATE KEY-----\n" + "MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCnlDycWB5VBGGy\n" + "oraDpmtVzEsEflFkDOimQIlliIgVwgitKsTs6Z94c07JBklLiBfgtX+ePfBI6onW\n" + "nMnaJjpuZL8pBiwMhH4qEv0Om0JxBGS85iMaMueUxMWKjM1b/HZ6d1QFBRoCSQCA\n" + "pYdtRH0j5VmeIMXRjvW9b7PWbIg0I30s7QdLXjH/PwGh7u+2guPn4hoXSCK79mEo\n" + "d/cdLODexLPa+H2rrJjp1VPevxCZoKWKKd96LEs+QWb1mCzRfxo5U2SlLpFg+bho\n" + "fdpcmDAXTMGcgkCS2iFEPgr+NzwhcYvCU8NgPUtuqQgRn+9vL5L9e1229lLiWdOA\n" + "7L1th9k1AgMBAAECggEAJfKG8R5xK+5Uk0eOTeyLBMBAwpE6LA5SRod5tYC/1DF+\n" + "lnwHYOCcaIGv9wyR32U/hvaCohpDhbd6pBsYCGq8s4/jy83mfqUoDq4DGOImnwIQ\n" + "L8hrbXzWfRU76F5vCGP4jk3kPEjF9XuDfh49twwZzF2cuBaSxRv64L1hO26TPz7l\n" + "qJ7f1cZ3K7vMghHtEsrmolw0MO2OgjL51IzV766+xmIvLM966kcIBEVvjQS76E2A\n" + "Mx67Iib7op2DpsxWt2E67zumbBPklIldT4pMdBtz/mHOT87Od/ADV6w7x7PxfFdp\n" + "QG8/FOEXALgDEyE3/mfUGnh3bFfnHGMm2LsGLM5agQKBgQDoI8ngAb27SiJ273pJ\n" + "gNwbXYOBmEGKVchwqlape2hatKn26Y/v3w3jGaMf8PS67NY/79vH7WLXGM6eXsaP\n" + "6s3041OJ5ppO5P6yS9Ohr+PrUxyXDdaKZaBJ7vMTvD/qfyrQbZXFjF6LKLQyKdGi\n" + "IVbavfzjP82pyoUZuKQy/kpKQQKBgQC4za8ujlHzaeAwK74At4/4rCF4FvFsAp7t\n" + "UXd8JX6wFHk5dEpy13IAY4nhJ7PgVtXBiy2LmhocNCAo3XmwXTWsQhdjuTexZ1MU\n" + "YSMlB0TOLvYHs5ewKSny8FFveYQjArb3xyuxdZQCKc3RxYrIcRU7npwf3wq5STI5\n" + "zlK4TjKJ9QKBgQDYMIxPTA/QnqgeL8SpM5LJAXv5czyGgoFbO6fdywpSfzJSuw3L\n" + "jOW3/CZJFvQ0KWEWxmDefpuwSnASWZ1+ZmRMjnE8WkCW/PieP7PmPpJ6lDpqCv8k\n" + "gKSYdip21LiJwMi0t3nmMmXSH6RBm2SaI4ZpzMn5MXBtkigG3kg9HUk+gQKBgQCU\n" + "WUCUTdkJXmeCI8sNhk1DYOIpJbm9a8kqVqhk9zBgpr69WVXeJIa2OzFWlel2YB6N\n" + "lG0GULk/BLUAOPHTmq9YTWG7QtarSXdOt79fnRslrFsBybAt0I2FIFcu9kwVUruP\n" + "4cl4VhtvNSGskDgdOXHC/0ry5rgUDucLsk2C9/rn9QKBgDqCd5etPAq8X61Kq5xW\n" + "uaxjXfcoW7RsPXDKxn+8+Tp7B/AhJB9UL2k/fqEG0BAbK63g5zk0q3g7HJTxofr+\n" + "WyMejeZuDrYaco+YI8k29BHqLraRikx887lYH8xVkSA8casVbjV8K317aWBJ2l8V\n" + "vadhWOmg7rGgufjuGhtScVnN" + "\n-----END PRIVATE KEY-----\n"
end

fun rsa_public() -> string
  "-----BEGIN PUBLIC KEY-----\n" + "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAp5Q8nFgeVQRhsqK2g6Zr\n" + "VcxLBH5RZAzopkCJZYiIFcIIrSrE7OmfeHNOyQZJS4gX4LV/nj3wSOqJ1pzJ2iY6\n" + "bmS/KQYsDIR+KhL9DptCcQRkvOYjGjLnlMTFiozNW/x2endUBQUaAkkAgKWHbUR9\n" + "I+VZniDF0Y71vW+z1myINCN9LO0HS14x/z8Boe7vtoLj5+IaF0giu/ZhKHf3HSzg\n" + "3sSz2vh9q6yY6dVT3r8QmaCliinfeixLPkFm9Zgs0X8aOVNkpS6RYPm4aH3aXJgw\n" + "F0zBnIJAktohRD4K/jc8IXGLwlPDYD1LbqkIEZ/vby+S/XtdtvZS4lnTgOy9bYfZ\n" + "NQIDAQAB" + "\n-----END PUBLIC KEY-----\n"
end

fun ec_private() -> string
  "-----BEGIN PRIVATE KEY-----\n" + "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgnzpR442PY33Tbjfy\n" + "RUdkmycsdCh2rROT37FJcP+MDR+hRANCAAQUZGRQ1uRfuRL44oi7NEf9lXBKKJ58\n" + "N9GJMPAY0NFfd494SVdEKynjERhnvRyBKB5I4wT8mOMLUPnx1XNx91I+" + "\n-----END PRIVATE KEY-----\n"
end

fun ec_public() -> string
  "-----BEGIN PUBLIC KEY-----\n" + "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEFGRkUNbkX7kS+OKIuzRH/ZVwSiie\n" + "fDfRiTDwGNDRX3ePeElXRCsp4xEYZ70cgSgeSOME/JjjC1D58dVzcfdSPg==" + "\n-----END PUBLIC KEY-----\n"
end

const SECRET = "your-256-bit-secret-your-256-bit-secret"

fun at(now: int) -> jwt.Options
  jwt.Options { now: now }
end

fun test_the_example_of_jwt_io_is_read_and_checked()
  -- HS256, secret "your-256-bit-secret": iat only, no exp
  let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
  -- its secret is shorter than 32: refused, as a rule of this module
  let short = jwt.Key.hs256("your-256-bit-secret")
  assert_eq(jwt.error_kind(jwt.verify(token, [short], at(1600000000)).unwrap_err()), "signature")
  -- the signature itself is the standard one: sign the same input with the same secret
  let signed = Hash.hmac_sha256_raw("your-256-bit-secret".to_bytes(), "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ".to_bytes())
  assert_eq(Base64.encode_url_bytes(signed), "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c")
end

fun test_a_signed_token_is_checked_and_its_claims_read()
  let key = jwt.Key.hs256(SECRET)
  let token = jwt.sign(Session { sub: "42", exp: 2000, scope: "read write" }, key).unwrap()
  assert_eq(token.split(".").len(), 3)
  let checked = jwt.verify(token, [key], at(1000)).unwrap()
  assert_eq(checked.subject(), "42")
  assert_eq(checked.scopes(), ["read", "write"])
  let s = checked.claims<Session>().unwrap()
  assert_eq(s.exp, 2000)
end

fun test_a_changed_token_or_another_secret_is_refused()
  let key = jwt.Key.hs256(SECRET)
  let token = jwt.sign(Session { sub: "42", exp: 2000 }, key).unwrap()
  let parts = token.split(".")
  let forged = jwt.sign(Session { sub: "1", exp: 2000 }, key).unwrap().split(".")
  let swapped = parts[0] + "." + forged[1] + "." + parts[2]
  assert_eq(jwt.error_kind(jwt.verify(swapped, [key], at(1000)).unwrap_err()), "signature")
  let other = jwt.Key.hs256("another-secret-another-secret-0123456789")
  assert_eq(jwt.error_kind(jwt.verify(token, [other], at(1000)).unwrap_err()), "signature")
  assert_eq(jwt.error_kind(jwt.verify("not.a.token", [key], at(1000)).unwrap_err()), "malformed")
  assert_eq(jwt.error_kind(jwt.verify("abc", [key], at(1000)).unwrap_err()), "malformed")
end

fun test_the_algorithm_comes_from_the_keys_not_from_the_token()
  let key = jwt.Key.hs256(SECRET)
  -- "none": a token without signature
  let none_header = Base64.encode_url_bytes("\{\"alg\":\"none\",\"typ\":\"JWT\"\}".to_bytes())
  let body = Base64.encode_url_bytes("\{\"sub\":\"1\",\"exp\":2000\}".to_bytes())
  assert_eq(jwt.error_kind(jwt.verify(none_header + "." + body + ".", [key], at(1000)).unwrap_err()), "algorithm")
  assert_eq(jwt.error_kind(jwt.verify(none_header + "." + body + ".AAAA", [key], at(1000)).unwrap_err()), "algorithm")
  -- the attack on RS256 servers: an HS256 token signed with the PUBLIC key as the secret
  let pub_pem = rsa_public()
  let forged = jwt.sign(Session { sub: "admin", exp: 2000 }, jwt.Key { alg: "HS256", key: pub_pem + "padding-to-be-long-enough" }).unwrap()
  let rs = jwt.Key.rs256(pub_pem)
  assert_eq(jwt.error_kind(jwt.verify(forged, [rs], at(1000)).unwrap_err()), "algorithm")
end

fun test_exp_nbf_issuer_and_audience_are_checked()
  let key = jwt.Key.hs256(SECRET)
  let full = jwt.sign_json(Json.object({"sub": Json.string("1"), "exp": Json.number(2000.0), "nbf": Json.number(1500.0), "iss": Json.string("https://auth.example"), "aud": Json.array([Json.string("api"), Json.string("web")])}), key).unwrap()
  assert_eq(jwt.error_kind(jwt.verify(full, [key], at(1000)).unwrap_err()), "not_yet_valid")
  assert_eq(jwt.verify(full, [key], jwt.Options { now: 1000, leeway: 600 }).is_ok(), true)
  assert_eq(jwt.verify(full, [key], at(1600)).is_ok(), true)
  assert_eq(jwt.error_kind(jwt.verify(full, [key], at(2000)).unwrap_err()), "expired")
  assert_eq(jwt.verify(full, [key], jwt.Options { now: 2100, leeway: 200 }).is_ok(), true)
  assert_eq(jwt.verify(full, [key], jwt.Options { now: 1600, issuer: "https://auth.example", audience: "web" }).is_ok(), true)
  assert_eq(jwt.error_kind(jwt.verify(full, [key], jwt.Options { now: 1600, issuer: "https://evil.example" }).unwrap_err()), "claims")
  assert_eq(jwt.error_kind(jwt.verify(full, [key], jwt.Options { now: 1600, audience: "admin" }).unwrap_err()), "claims")
  let forever = jwt.sign_json(Json.object({"sub": Json.string("1")}), key).unwrap()
  assert_eq(jwt.error_kind(jwt.verify(forever, [key], at(1000)).unwrap_err()), "claims")
  assert_eq(jwt.verify(forever, [key], jwt.Options { now: 1000, require_exp: false }).is_ok(), true)
end

fun test_a_short_hmac_secret_is_refused()
  let r = jwt.sign(Session { sub: "1", exp: 1 }, jwt.Key.hs256("short"))
  assert(r.unwrap_err().message.contains("32"))
end

fun test_rsa_and_ec_keys_sign_and_verify()
  let rs = jwt.sign(Session { sub: "r", exp: 2000 }, jwt.Key.rs256(rsa_private())).unwrap()
  assert_eq(jwt.verify(rs, [jwt.Key.rs256(rsa_public())], at(1000)).unwrap().subject(), "r")
  let es = jwt.sign(Session { sub: "e", exp: 2000 }, jwt.Key.es256(ec_private())).unwrap()
  assert_eq(jwt.verify(es, [jwt.Key.es256(ec_public())], at(1000)).unwrap().subject(), "e")
  -- an RS256 token is not accepted by an ES256 key
  assert_eq(jwt.error_kind(jwt.verify(rs, [jwt.Key.es256(ec_public())], at(1000)).unwrap_err()), "algorithm")
end

fun test_the_kid_of_the_header_picks_the_key()
  let one = jwt.Key.hs256(SECRET).named("2025")
  let two = jwt.Key.hs256("a-newer-secret-a-newer-secret-0123456789").named("2026")
  let token = jwt.sign(Session { sub: "1", exp: 2000 }, two).unwrap()
  assert_eq(jwt.verify(token, [one, two], at(1000)).is_ok(), true)
  assert_eq(jwt.error_kind(jwt.verify(token, [one], at(1000)).unwrap_err()), "key")
  let old = jwt.sign(Session { sub: "1", exp: 2000 }, one).unwrap()
  assert_eq(jwt.verify(old, [one, two], at(1000)).is_ok(), true)
end

fun test_a_jwks_gives_keys_that_verify_tokens()
  -- the public EC key of the tests, as a JWK (x and y of the point)
  let spki = Base64.decode_bytes(ec_public().replace("-----BEGIN PUBLIC KEY-----", "").replace("-----END PUBLIC KEY-----", "").replace("\n", "")) ?? bytes.empty()
  assert_eq(spki.len(), 91)
  let point = spki.slice(26, 91)
  let x = Base64.encode_url_bytes(point.slice(1, 33))
  let y = Base64.encode_url_bytes(point.slice(33, 65))
  let doc = "\{\"keys\":[\{\"kty\":\"EC\",\"crv\":\"P-256\",\"kid\":\"k1\",\"use\":\"sig\",\"x\":\"{x}\",\"y\":\"{y}\"\},\{\"kty\":\"RSA\",\"kid\":\"enc\",\"use\":\"enc\",\"n\":\"AQAB\",\"e\":\"AQAB\"\}]\}"
  let keys = jwt.keys_from_jwks(doc).unwrap()
  assert_eq(keys.len(), 1)
  assert_eq(keys[0].alg, "ES256")
  assert_eq(keys[0].kid, "k1")
  let token = jwt.sign(Session { sub: "g", exp: 2000 }, jwt.Key.es256(ec_private()).named("k1")).unwrap()
  assert_eq(jwt.verify(token, keys, at(1000)).unwrap().subject(), "g")
end

fun test_hs384_hs512_and_pss_tokens_are_signed_and_checked()
  let long = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  for key in [jwt.Key.hs384(long), jwt.Key.hs512(long), jwt.Key.ps256(rsa_private()), jwt.Key.ps384(rsa_private()), jwt.Key.ps512(rsa_private())] do
    let token = jwt.sign(Session { sub: "7", exp: 2000 }, key).unwrap()
    let check = if key.alg.starts_with("HS") then key else public_key(key.alg) end
    assert_eq(jwt.verify(token, [check], at(1000)).unwrap().subject(), "7")
  end
  -- a secret shorter than the hash is refused, in both directions
  assert(jwt.sign(Session { sub: "7", exp: 2000 }, jwt.Key.hs512("short")).is_err())
  let token = jwt.sign(Session { sub: "7", exp: 2000 }, jwt.Key.hs384(long)).unwrap()
  -- HS384 is not accepted where only HS512 is expected
  assert_eq(jwt.error_kind(jwt.verify(token, [jwt.Key.hs512(long)], at(1000)).unwrap_err()), "algorithm")
end

fun public_key(alg: string) -> jwt.Key
  jwt.Key { alg: alg, key: rsa_public() }
end

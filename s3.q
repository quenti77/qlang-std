--" # S3 storage

Reads, writes and deletes objects in an S3 bucket (Amazon S3, Cloudflare R2, MinIO, Backblaze B2, Scaleway,
DigitalOcean Spaces: anything that speaks the S3 API), signing each request with AWS Signature Version 4.

```
let bucket = S3.new("https://s3.eu-west-3.amazonaws.com", "eu-west-3", key_id, secret, "my-bucket")
bucket.put("reports/2026.txt", "hello", "text/plain").unwrap()
let text = bucket.get("reports/2026.txt").unwrap()        -- string?  (none: no such object)
bucket.delete("reports/2026.txt").unwrap()

-- a browser uploads or downloads by itself, with a link that works for a few minutes
let upload = bucket.presign("PUT", "avatars/42.png", 300)
```

`put` and `get` carry text; `put_bytes` and `get_bytes` carry any file (images, PDFs). For big files do not
go through your server at all: give the browser a **presigned URL** (`presign`), and it sends or fetches the
bytes straight to the bucket. The bucket must allow your site in its CORS settings for that.

Keys are written in the path (`https://endpoint/bucket/key`), which every S3-compatible service accepts. With
an endpoint that already names the bucket (`https://my-bucket.s3.amazonaws.com`), give `""` as the bucket.
--"

type Transport = fun(Request) -> Result<Response, Error>

--" A bucket. --"
struct S3
  public endpoint: string
  public region: string
  public access_key: string
  public secret: string
  public bucket: string
  public transport: Transport
  --" The time in milliseconds; tests give their own. --"
  public clock: fun() -> int
end

fun s3_error<T>(message: string) -> Result<T, Error>
  Result<T, Error>.Err(Error { message: message })
end

-- Percent-encoding as AWS wants it: everything but A-Z a-z 0-9 - _ . ~
fun aws_encode(text: string) -> string
  Url.encode(text).replace("!", "%21").replace("'", "%27").replace("(", "%28").replace(")", "%29").replace("*", "%2A")
end

fun path_of(key: string) -> string
  "/" + key.split("/").map(fun(part: string) -> string aws_encode(part) end).join("/")
end

fun hmac(key: bytes, message: string) -> bytes
  Hash.hmac_sha256_raw(key, message.to_bytes())
end

fun host_of(endpoint: string) -> string
  endpoint.replace("https://", "").replace("http://", "").split("/")[0]
end

impl S3
  public fun new(endpoint: string, region: string, access_key: string, secret: string, bucket: string) -> S3
    S3 { endpoint: endpoint, region: region, access_key: access_key, secret: secret, bucket: bucket, transport: fun(r: Request) -> Result<Response, Error> http.send(r) end, clock: fun() -> int time.now() end }
  end

  fun signing_key(self, day: string) -> bytes
    let date = hmac("AWS4{self.secret}".to_bytes(), day)
    let region = hmac(date, self.region)
    let service = hmac(region, "s3")
    hmac(service, "aws4_request")
  end

  fun base(self) -> string
    if self.endpoint.ends_with("/") then self.endpoint.substring(0, self.endpoint.len() - 1) else self.endpoint end
  end

  fun path(self, key: string) -> string
    if self.bucket == "" then path_of(key) else "/" + aws_encode(self.bucket) + path_of(key) end
  end

  --" The headers of a signed request (`Authorization`, `x-amz-date`, `x-amz-content-sha256`). --"
  public fun sign(self, method: string, key: string, body: string, extra: map<string, string>) -> map<string, string>
    self.sign_hash(method, key, Hash.sha256(body), extra)
  end

  --" Like `sign`, for a body whose SHA-256 (in hexadecimal) you already have. --"
  public fun sign_hash(self, method: string, key: string, payload: string, extra: map<string, string>) -> map<string, string>
    let moment = datetime.at(self.clock())
    let stamp = moment.format("YYYYMMDDTHHmmssZ")
    let day = moment.format("YYYYMMDD")
    let headers: map<string, string> = {"host": host_of(self.endpoint), "x-amz-content-sha256": payload, "x-amz-date": stamp}
    for k in extra.keys() do
      headers[k.lower()] = (extra[k] ?? "").trim()
    end
    let names = headers.keys()
    names.sort()
    let canonical_headers = names.map(fun(n: string) -> string "{n}:{headers[n] ?? ""}\n" end).join("")
    let signed = names.join(";")
    let canonical = "{method}\n{self.path(key)}\n\n{canonical_headers}\n{signed}\n{payload}"
    let scope = "{day}/{self.region}/s3/aws4_request"
    let to_sign = "AWS4-HMAC-SHA256\n{stamp}\n{scope}\n{Hash.sha256(canonical)}"
    let signature = Hex.encode_bytes(hmac(self.signing_key(day), to_sign))
    let out: map<string, string> = {}
    for n in names do
      if n != "host" then
        out[n] = headers[n] ?? ""
      end
    end
    out["Authorization"] = "AWS4-HMAC-SHA256 Credential={self.access_key}/{scope}, SignedHeaders={signed}, Signature={signature}"
    out
  end

  fun usable(key: string) -> bool
    not (key == "" or key.starts_with("/") or key.contains(".."))
  end

  fun call(self, method: string, key: string, body: string, extra: map<string, string>) -> Result<Response, Error>
    if not S3.usable(key) then
      return s3_error<Response>("`{key}` is not a usable key")
    end
    self.transport(Request { method: method, url: "{self.base()}{self.path(key)}", headers: self.sign(method, key, body, extra), body: if body == "" then none else body end })
  end

  --" Writes the object (text). --"
  public fun put(self, key: string, body: string, content_type: string) -> Result<bool, Error>
    let r = self.call("PUT", key, body, {"content-type": content_type})
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    if r.unwrap().status >= 300 then
      return s3_error<bool>("S3 answered {r.unwrap().status}: {r.unwrap().body}")
    end
    Result<bool, Error>.Ok(true)
  end

  --" Writes the object from bytes (any file). --"
  public fun put_bytes(self, key: string, data: bytes, content_type: string) -> Result<bool, Error>
    if not S3.usable(key) then
      return s3_error<bool>("`{key}` is not a usable key")
    end
    let r = self.transport(Request { method: "PUT", url: "{self.base()}{self.path(key)}", headers: self.sign_hash("PUT", key, Hash.sha256_bytes(data), {"content-type": content_type}), raw: data })
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    if r.unwrap().status >= 300 then
      return s3_error<bool>("S3 answered {r.unwrap().status}: {r.unwrap().body}")
    end
    Result<bool, Error>.Ok(true)
  end

  --" The object as bytes, or `none` when it does not exist. --"
  public fun get_bytes(self, key: string) -> Result<bytes?, Error>
    let r = self.call("GET", key, "", {})
    if r.is_err() then
      return Result<bytes?, Error>.Err(r.unwrap_err())
    end
    let res = r.unwrap()
    if res.status == 404 then
      return Result<bytes?, Error>.Ok(none)
    end
    if res.status >= 300 then
      return s3_error<bytes?>("S3 answered {res.status}")
    end
    let raw = res.raw
    Result<bytes?, Error>.Ok(if raw == none then res.body.to_bytes() else raw end)
  end

  --" The object as text, or `none` when it does not exist. --"
  public fun get(self, key: string) -> Result<string?, Error>
    let r = self.call("GET", key, "", {})
    if r.is_err() then
      return Result<string?, Error>.Err(r.unwrap_err())
    end
    if r.unwrap().status == 404 then
      return Result<string?, Error>.Ok(none)
    end
    if r.unwrap().status >= 300 then
      return s3_error<string?>("S3 answered {r.unwrap().status}: {r.unwrap().body}")
    end
    Result<string?, Error>.Ok(r.unwrap().body)
  end

  --" Whether the object exists. --"
  public fun exists(self, key: string) -> Result<bool, Error>
    let r = self.call("HEAD", key, "", {})
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    if r.unwrap().status == 404 then
      return Result<bool, Error>.Ok(false)
    end
    if r.unwrap().status >= 300 then
      return s3_error<bool>("S3 answered {r.unwrap().status}")
    end
    Result<bool, Error>.Ok(true)
  end

  --" Deletes the object (also fine when it was not there). --"
  public fun delete(self, key: string) -> Result<bool, Error>
    let r = self.call("DELETE", key, "", {})
    if r.is_err() then
      return Result<bool, Error>.Err(r.unwrap_err())
    end
    if r.unwrap().status >= 300 and r.unwrap().status != 404 then
      return s3_error<bool>("S3 answered {r.unwrap().status}: {r.unwrap().body}")
    end
    Result<bool, Error>.Ok(true)
  end

  --" A link that lets whoever has it do `method` (`GET`, `PUT`, `DELETE`) on the object for `seconds`
  (at most 7 days), without any key: for a browser that uploads or downloads by itself. --"
  public fun presign(self, method: string, key: string, seconds: int) -> string
    let moment = datetime.at(self.clock())
    let stamp = moment.format("YYYYMMDDTHHmmssZ")
    let day = moment.format("YYYYMMDD")
    let scope = "{day}/{self.region}/s3/aws4_request"
    let life = if seconds > 604800 then 604800 else (if seconds < 1 then 1 else seconds end) end
    let params: array<(string, string)> = [("X-Amz-Algorithm", "AWS4-HMAC-SHA256"), ("X-Amz-Credential", "{self.access_key}/{scope}"), ("X-Amz-Date", stamp), ("X-Amz-Expires", "{life}"), ("X-Amz-SignedHeaders", "host")]
    let query = params.map(fun(p: (string, string)) -> string "{aws_encode(p.0)}={aws_encode(p.1)}" end).join("&")
    let canonical = "{method}\n{self.path(key)}\n{query}\nhost:{host_of(self.endpoint)}\n\nhost\nUNSIGNED-PAYLOAD"
    let to_sign = "AWS4-HMAC-SHA256\n{stamp}\n{scope}\n{Hash.sha256(canonical)}"
    let signature = Hex.encode_bytes(hmac(self.signing_key(day), to_sign))
    "{self.base()}{self.path(key)}?{query}&X-Amz-Signature={signature}"
  end
end

export S3, Transport

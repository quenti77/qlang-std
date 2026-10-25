import "s3.q" as s3

-- The examples of the AWS documentation (Signature Version 4, S3), made with these keys and this date.
fun example() -> s3.S3
  let b = s3.S3.new("https://examplebucket.s3.amazonaws.com", "us-east-1", "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", "")
  b.clock = fun() -> int 1369353600000 end
  b
end

fun test_a_signed_get_matches_the_aws_documentation()
  let headers = example().sign("GET", "test.txt", "", {"range": "bytes=0-9"})
  assert_eq(headers["Authorization"], "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
  assert_eq(headers["x-amz-date"], "20130524T000000Z")
end

fun test_a_signed_put_matches_the_aws_documentation()
  let headers = example().sign("PUT", "test$file.text", "Welcome to Amazon S3.", {"date": "Fri, 24 May 2013 00:00:00 GMT", "x-amz-storage-class": "REDUCED_REDUNDANCY"})
  assert_eq(headers["Authorization"], "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class, Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")
end

fun test_a_presigned_url_matches_the_aws_documentation()
  let url = example().presign("GET", "test.txt", 86400)
  assert_eq(url, "https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404")
end

fun spy(seen: array<Request>, status: int, body: string) -> s3.Transport
  fun(r: Request) -> Result<Response, Error>
    seen.push(r)
    Result<Response, Error>.Ok(Response { status: status, body: body })
  end
end

fun test_the_calls_use_the_path_of_the_bucket_and_read_the_answers()
  let seen: array<Request> = []
  let b = s3.S3.new("https://s3.example.org/", "eu-west-3", "id", "secret", "my-bucket")
  b.transport = spy(seen, 200, "hello")
  assert_eq(b.get("a b/c.txt").unwrap(), "hello")
  assert_eq(seen[0].url, "https://s3.example.org/my-bucket/a%20b/c.txt")
  assert((seen[0].headers["Authorization"] ?? "").starts_with("AWS4-HMAC-SHA256 Credential=id/"))
  b.put("k", "x", "text/plain").unwrap()
  assert_eq(seen[1].method, "PUT")
  b.transport = spy(seen, 404, "")
  assert(b.get("missing").unwrap() == none)
  assert_eq(b.exists("missing").unwrap(), false)
  assert_eq(b.delete("missing").unwrap(), true)
  b.transport = spy(seen, 403, "denied")
  assert(b.put("k", "x", "text/plain").unwrap_err().message.contains("403"))
end

fun test_keys_that_could_escape_the_bucket_are_refused()
  let seen: array<Request> = []
  let b = s3.S3.new("https://s3.example.org", "r", "id", "secret", "bkt")
  b.transport = spy(seen, 200, "")
  assert(b.get("../other").is_err())
  assert(b.get("/abs").is_err())
  assert(b.get("").is_err())
  assert_eq(seen.len(), 0)
end

fun test_bytes_are_signed_by_their_own_hash_and_read_back_raw()
  let seen: array<Request> = []
  let b = s3.S3.new("https://s3.example.org", "r", "id", "secret", "bkt")
  b.transport = fun(r: Request) -> Result<Response, Error>
    seen.push(r)
    Result<Response, Error>.Ok(Response { status: 200, body: "", raw: "PNG".to_bytes() })
  end
  let data = "binary".to_bytes()
  b.put_bytes("a.png", data, "image/png").unwrap()
  assert_eq(seen[0].headers["x-amz-content-sha256"], Hash.sha256_bytes(data))
  assert(seen[0].raw != none)
  assert_eq((b.get_bytes("a.png").unwrap() ?? "".to_bytes()).to_string(), "PNG")
  assert(b.put_bytes("../x", data, "image/png").is_err())
end

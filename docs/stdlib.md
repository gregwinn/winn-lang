# Winn Standard Library

## IO

### `IO.puts(string)`
Print a string followed by a newline.
```winn
IO.puts("Hello, World!")
```

### `IO.print(value)`
Print a value without a newline.

### `IO.inspect(value)`
Print a debug representation of any value. Returns the value unchanged (useful in pipes).
```winn
list
  |> IO.inspect()
  |> Enum.map() do |x| x * 2 end
```

---

## String

### `String.upcase(str)` / `String.downcase(str)`
```winn
String.upcase("hello")    # => "HELLO"
String.downcase("WORLD")  # => "world"
```

### `String.trim(str)`
Remove leading and trailing whitespace.

### `String.length(str)`
Return the number of characters.

### `String.split(str, delimiter)`
Split a string into a list.
```winn
String.split("a,b,c", ",")  # => ["a", "b", "c"]
```

### `String.contains?(str, substring)`
```winn
String.contains?("hello world", "world")  # => true
```

### `String.replace(str, pattern, replacement)`
Replace all occurrences.
```winn
String.replace("foo bar foo", "foo", "baz")  # => "baz bar baz"
```

### `String.starts_with?(str, prefix)` / `String.ends_with?(str, suffix)`
```winn
String.starts_with?("hello", "he")  # => true
String.ends_with?("hello", "lo")    # => true
```

### `String.slice(str, start, length)`
```winn
String.slice("hello world", 6, 5)  # => "world"
```
Out-of-range start, negative start, negative length, or a non-binary input return `""` rather than crashing.

### `String.to_integer(str)` / `String.to_float(str)`
Parse strings to numbers.

---

## Enum

All Enum functions take a list as the first argument and a block/function as the last.

### `Enum.map(list) do |x| expr end`
Transform each element.
```winn
Enum.map([1, 2, 3]) do |x| x * 2 end
# => [2, 4, 6]
```

### `Enum.filter(list) do |x| predicate end`
Keep elements where predicate is truthy.
```winn
Enum.filter([1, 2, 3, 4]) do |x| x > 2 end
# => [3, 4]
```

### `Enum.reduce(list, acc) do |x, acc| expr end`
Fold a list into a single value.
```winn
Enum.reduce([1, 2, 3, 4, 5], 0) do |x, acc| x + acc end
# => 15
```

### `Enum.each(list) do |x| expr end`
Iterate for side effects. Returns `:ok`.
```winn
Enum.each(names) do |name|
  IO.puts("Hello, " <> name)
end
```

### `Enum.find(list) do |x| predicate end`
Return `{:ok, element}` for the first match, or `:not_found`.

### `Enum.any?(list) do |x| predicate end` / `Enum.all?(list) do |x| predicate end`
Check if any/all elements match a predicate.

### `Enum.count(list)`
Return the number of elements.

### `Enum.sort(list)` / `Enum.sort(list) do |a, b| a < b end`
Sort a list, optionally with a comparator.

### `Enum.reverse(list)`
Reverse a list.

### `Enum.join(list, separator)`
Join list elements into a string.
```winn
Enum.join(["a", "b", "c"], ", ")  # => "a, b, c"
```

### `Enum.flat_map(list) do |x| list end`
Map then flatten one level.

---

## List

### `List.first(list)` / `List.last(list)`
Return the first/last element, or `nil` for empty lists.

### `List.length(list)`
Return the number of elements.

### `List.reverse(list)`
Reverse the list.

### `List.flatten(list)`
Flatten nested lists one level deep.

### `List.append(list1, list2)`
Concatenate two lists.

### `List.contains?(list, element)`
Check if an element is in the list.

---

## Map

### `Map.merge(map1, map2)`
Merge two maps. Keys in `map2` override `map1`.
```winn
Map.merge(%{a: 1}, %{b: 2})  # => %{a: 1, b: 2}
```

### `Map.get(key, map)`
Get a value by key. Returns `nil` if the key is missing, or `{error, :not_a_map}` if the second argument is not a map.

### `Map.put(key, value, map)`
Return a new map with the key set.

### `Map.keys(map)` / `Map.values(map)`
Return all keys or values as a list.

### `Map.has_key?(key, map)`
Check if a key exists.

### `Map.delete(key, map)`
Return a new map with the key removed.

---

## System

### `System.get_env(key)`
Read an environment variable. Returns the value as a string, or `nil` if not set.
```winn
port = System.get_env("PORT")
# => "4000" or nil
```

### `System.get_env(key, default)`
Read with a default value.
```winn
port = System.get_env("PORT", "3000")
```

### `System.put_env(key, value)`
Set an environment variable.
```winn
System.put_env("DEBUG", "true")
```

---

## UUID

### `UUID.v4()`
Generate a random UUID v4 string.
```winn
id = UUID.v4()
# => "550e8400-e29b-41d4-a716-446655440000"
```

---

## DateTime

### `DateTime.now()`
Returns the current Unix timestamp in seconds.
```winn
now = DateTime.now()
# => 1711540800
```

### `DateTime.to_iso8601(timestamp)`
Convert a Unix timestamp to an ISO 8601 string.
```winn
DateTime.to_iso8601(1704067200)
# => "2024-01-01T00:00:00Z"
```

### `DateTime.from_iso8601(string)`
Parse an ISO 8601 string to a Unix timestamp.
```winn
{:ok, ts} = DateTime.from_iso8601("2024-01-01T00:00:00Z")
# ts => 1704067200
```

### `DateTime.diff(t1, t2)`
Returns the difference in seconds between two timestamps.
```winn
diff = DateTime.diff(later, earlier)
# => 3600  (1 hour)
```

### `DateTime.format(timestamp, format_string)`
Format a timestamp using strftime-style directives (`%Y`, `%m`, `%d`, `%H`, `%M`, `%S`).
```winn
DateTime.format(ts, "%Y-%m-%d")
# => "2024-01-01"

DateTime.format(ts, "%Y-%m-%d %H:%M:%S")
# => "2024-01-01 00:00:00"
```

---

## Logger

Structured JSON logging to stderr. Each log line includes a timestamp, level, message, and optional metadata.

### `Logger.info(message)` / `Logger.info(message, metadata)`
```winn
Logger.info("user created")
Logger.info("user created", %{user_id: 42})
```

Output:
```json
{"level":"info","msg":"user created","user_id":42,"ts":"2026-03-27T12:00:00Z"}
```

### `Logger.warn(message)` / `Logger.warn(message, metadata)`
```winn
Logger.warn("slow query", %{duration_ms: 450})
```

### `Logger.error(message)` / `Logger.error(message, metadata)`
```winn
Logger.error("db connection failed", %{reason: "timeout"})
```

### `Logger.debug(message)` / `Logger.debug(message, metadata)`
```winn
Logger.debug("checkpoint", %{step: 3})
```

---

## Crypto

### `Crypto.hash(algorithm, data)`
Hash data with the given algorithm. Returns a hex-encoded binary.
Supported algorithms: `:sha256`, `:sha384`, `:sha512`, `:sha`, `:md5`.
```winn
hash = Crypto.hash(:sha256, "hello")
# => "2cf24dba5fb0a30e26e83b2ac5b9e29e..."
```

### `Crypto.hmac(algorithm, key, data)`
Compute an HMAC. Returns a hex-encoded binary.
```winn
hmac = Crypto.hmac(:sha256, "secret", "data")
```

### `Crypto.random_bytes(n)`
Generate `n` cryptographically secure random bytes.
```winn
token = Crypto.random_bytes(32)
```

### `Crypto.base64_encode(binary)` / `Crypto.base64_decode(string)`
Base64 encode and decode.
```winn
encoded = Crypto.base64_encode(token)
decoded = Crypto.base64_decode(encoded)
```

### `Crypto.hash_password(password)`
Hash a password for storage using PBKDF2-HMAC-SHA256 (600,000 iterations) with a
fresh random 16-byte salt. Returns a self-describing PHC-style string — the algorithm,
iteration count, salt, and derived key all travel together, so the cost can be raised
later without invalidating existing hashes. Hashing the same password twice yields
different strings. **Do not** use `Crypto.hash(:sha256, ...)` for passwords.
```winn
hash = Crypto.hash_password("hunter2")
# => "$pbkdf2-sha256$i=600000$<salt_b64>$<hash_b64>"
```

### `Crypto.verify_password(password, hash)`
Verify a password against a stored `hash_password` string. Recomputes the derivation
using the salt and iteration count embedded in the hash and compares in constant time.
Returns `true` or `false`; a malformed or non-string hash returns `false` rather than
crashing, so it is safe to call on stored data.
```winn
if Crypto.verify_password(password, user.password_hash)
  # ... issue a token
end
```

---

## Auth

Email/password login built on `Crypto`, `JWT`, and `Repo`. Expects a `user` schema
with `email` and `password_hash` fields and a signing secret in config
(`Config.put(:auth, :secret, ...)`). See the [Auth guide](modules.md#auth) for the
full router + frontend example.

### `Auth.register(email, password)`
Hash the password and create a user. Returns the user (without `password_hash`),
or `{:error, :email_taken}`.
```winn
Auth.register("alice@example.com", "hunter2")
```

### `Auth.login(email, password)`
Verify credentials and return `%{user: ..., access_token: token}`, or
`{:error, :invalid_credentials}` (same error for wrong password and unknown email).
```winn
Auth.login("alice@example.com", "hunter2")
```

### `Auth.current_user(conn)`
Resolve the authenticated user from the conn's verified JWT claims (attached by the
`[:auth]` middleware). Returns the user or `{:error, :unauthenticated}`.
```winn
Auth.current_user(conn)
```

---

## JSON

### `JSON.encode(term)`
Encode a map, list, or value to a JSON binary string. Atom keys are converted to strings.
```winn
JSON.encode(%{name: "Alice", age: 30})
# => "{\"name\":\"Alice\",\"age\":30}"
```

### `JSON.decode(binary)`
Decode a JSON binary string to a map with atom keys.
```winn
data = JSON.decode("{\"name\":\"Bob\",\"count\":5}")
data.name   # => "Bob"
data.count  # => 5
```

---

## Metrics

Counters, gauges, histograms, and HTTP request stats. ETS-backed for concurrent reads with no locking. Combine with `winn_logger` to get observability comparable to a typical production OTP service.

Call `Metrics.enable()` once at app start (the CLI's `start` command does this automatically) before recording metrics.

### `Metrics.increment(name)` / `Metrics.increment(name, amount)`
Increment a counter. `amount` defaults to 1.
```winn
Metrics.increment(:requests)
Metrics.increment(:bytes_sent, 1024)
```

### `Metrics.set(name, value)`
Set a gauge to an absolute value.
```winn
Metrics.set(:queue_depth, 42)
```

### `Metrics.observe(name, value)`
Record a sample in a histogram (e.g. for latency tracking). The most recent 1000 samples are retained per name.
```winn
Metrics.observe(:request_ms, 12.5)
```

### `Metrics.time(name, fun)`
Time the execution of a zero-arity lambda and `observe` the elapsed milliseconds. Returns the lambda's result.
```winn
result = Metrics.time(:db_query, fn -> Repo.all(User) end)
```

### `Metrics.get(name)`
Read a counter or gauge by name. Returns `0` if not found.
```winn
Metrics.get(:requests)  # => 42
```

### `Metrics.snapshot()`
Return a map with all counters, gauges, and histogram summaries (`p50`, `p95`, `p99`, `count`, `avg`, `min`, `max`).
```winn
%{counters: counters, gauges: gauges, histograms: hist} = Metrics.snapshot()
```

### `Metrics.beam_stats()`
Process count, memory breakdown, atom counts, scheduler count, and uptime — useful for runtime diagnostics dashboards.

### `Metrics.prometheus()`
Render the full metrics state as a Prometheus v0.0.4 text exposition binary. Wire it into a `/metrics` endpoint with one line:

```winn
module MyApp.Router
  use Winn.Router

  def routes()
    [{:get, "/metrics", :metrics}]
  end

  def metrics(conn)
    Server.text(conn, Metrics.prometheus())
  end
end
```

Output covers counters, gauges, histograms (as Prometheus summaries with `quantile="0.5|0.95|0.99"` labels), per-endpoint HTTP stats (`http_requests_total`, `http_errors_total`, `http_request_duration_ms`), and BEAM gauges (`beam_process_count`, `beam_memory_*_bytes`, `beam_uptime_ms`). Float values use 3-decimal compact form. See [deployment.md](deployment.md) for the full Prometheus + Kubernetes wiring.

---

## Type Conversions

These are available as bare function calls anywhere in Winn code:

```winn
to_string(42)        # => "42"
to_string(:hello)    # => "hello"
to_integer("123")    # => 123
to_float(5)          # => 5.0
to_atom("hello")     # => :hello
inspect({:ok, 42})   # => "{ok,42}"
```

Also available via module prefix:

- `String.to_integer(str)` — parse integer
- `String.to_float(str)` — parse float

## Testing

### `assert(expr)`
Assert that `expr` is `true`. Raises an assertion error on `false`.

```winn
assert(1 + 1 == 2)
```

### `assert_equal(expected, actual)`
Assert that two values are strictly equal (`=:=`). On failure, shows the expected and actual values.

```winn
assert_equal("hello", String.downcase("HELLO"))
```

### `use Winn.Test`
Marks a module as a test module. Test functions must be named `test_*` with zero arguments.

```winn
module UserTest
  use Winn.Test

  def test_greeting()
    result = "Hello, " <> "Alice"
    assert_equal("Hello, Alice", result)
  end
end
```

Run with `winn test`. See [CLI Reference](cli.md#winn-test-file) for details.

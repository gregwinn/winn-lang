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
Return the first/last element, or `:not_found` for empty lists.

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
Get a value by key.

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

---

## Type Conversions

These are global functions (no module prefix needed from Erlang; in Winn call via the runtime):

- `String.to_integer(str)` — parse integer
- `String.to_float(str)` — parse float

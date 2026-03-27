# Winn Modules

Higher-level modules for building web services, APIs, and concurrent applications.

---

## HTTP Client

Make HTTP requests with automatic JSON encoding/decoding. Powered by [hackney](https://github.com/benoitc/hackney) and [jsone](https://github.com/sile/jsone).

### `HTTP.get(url)`

```winn
match HTTP.get("https://api.example.com/users")
  ok resp => IO.inspect(resp.body)
  err reason => IO.puts("request failed")
end
```

### `HTTP.post(url, body)`

Map bodies are automatically JSON-encoded:

```winn
match HTTP.post("https://api.example.com/users", %{name: "Alice", email: "alice@example.com"})
  ok resp => resp.body
  err reason => {:error, reason}
end
```

### `HTTP.put(url, body)` / `HTTP.patch(url, body)` / `HTTP.delete(url)`

Same pattern as `get` and `post`.

### `HTTP.request(method, url, body)`

Low-level request. `method` is an atom (`:get`, `:post`, `:put`, `:patch`, `:delete`). `body` is a map (JSON-encoded), binary, or `nil`.

### Response Format

All HTTP functions return `{:ok, response}` or `{:error, reason}`.

The response is a map:

```winn
%{
  status: 200,           # HTTP status code (integer)
  body: %{...},          # decoded JSON map, or raw binary
  headers: %{...}        # lowercase header names -> values
}
```

JSON responses (Content-Type containing "json") are automatically decoded into maps.

---

## Config

ETS-backed configuration system for application settings.

### `Config.get(section, key)`

Get a config value. Returns `nil` if not found.

```winn
port = Config.get(:http, :port)
# => 4000 or nil
```

### `Config.get(section, key, default)`

Get with a default:

```winn
port = Config.get(:http, :port, 3000)
```

### `Config.put(section, key, value)`

Set a config value:

```winn
Config.put(:http, :port, 4000)
```

### `Config.load(config_map)`

Bulk-load config from a nested map:

```winn
Config.load(%{
  database: %{pool_size: 10, timeout: 5000},
  http: %{port: 4000}
})
```

---

## Task / Async

Run concurrent work without writing GenServer code.

### `Task.spawn(fun)`

Fire and forget — spawns a process, returns its pid.

```winn
Task.spawn() do ||
  IO.puts("background work")
end
```

### `Task.async(fun)` + `Task.await(handle)`

Spawn a task and wait for its result:

```winn
handle = Task.async() do ||
  expensive_computation()
end
result = Task.await(handle)
```

### `Task.await(handle, timeout_ms)`

Await with an explicit timeout. Returns `{:error, :timeout}` if the task doesn't complete in time.

```winn
result = Task.await(handle, 5000)
```

### `Task.async_all(list, fun)`

Parallel map — runs the function on each element concurrently, returns results in order:

```winn
results = Task.async_all([1, 2, 3]) do |id|
  fetch_user(id)
end
# => [user1, user2, user3]
```

---

## JWT

Pure Erlang HS256 JSON Web Token implementation. No external dependencies.

### `JWT.sign(claims, secret)`

Sign a claims map and return a JWT token string:

```winn
token = JWT.sign(%{user_id: 42, role: :admin}, "my_secret")
# => "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjo0Mn0...."
```

Include an `exp` field (Unix timestamp) to create expiring tokens:

```winn
exp = DateTime.now() + 3600
token = JWT.sign(%{user_id: 42, exp: exp}, secret)
```

### `JWT.verify(token, secret)`

Verify a token's signature and check expiry. Returns `{:ok, claims}` or `{:error, reason}`.

```winn
match JWT.verify(token, secret)
  ok claims => claims
  err :expired => {:error, :token_expired}
  err :invalid_signature => {:error, :unauthorized}
  err _ => {:error, :invalid_token}
end
```

Possible errors: `:invalid_signature`, `:expired`, `:invalid_token`, `:malformed_token`.

### Security

- Signatures use HMAC-SHA256 via the OTP `crypto` module
- Signature comparison is constant-time to prevent timing attacks
- Expiry (`exp` claim) is checked automatically during verification

---

## WebSockets

WebSocket client powered by [gun](https://github.com/ninenines/gun). Supports `ws://` and `wss://`.

### `WS.connect(url)`

Open a WebSocket connection:

```winn
match WS.connect("wss://api.example.com/ws")
  ok conn => conn
  err reason => IO.puts("connection failed")
end
```

### `WS.send(conn, data)`

Send a message. Maps are automatically JSON-encoded:

```winn
WS.send(conn, %{type: :subscribe, channel: "prices"})
WS.send(conn, "plain text message")
```

### `WS.recv(conn)` / `WS.recv(conn, timeout_ms)`

Receive the next message. Default timeout is 5 seconds.

```winn
match WS.recv(conn)
  ok msg  => IO.inspect(msg)
  err :timeout => IO.puts("no message")
  err :closed => IO.puts("disconnected")
end
```

### `WS.close(conn)`

Close the connection:

```winn
WS.close(conn)
```

### WebSocket Handler (Server-side)

Define a WebSocket handler module with `use Winn.WebSocket`:

```winn
module MyApp.WsHandler
  use Winn.WebSocket

  def on_connect(conn)
    {:ok, %{conn: conn}}
  end

  def on_message(msg, state)
    IO.inspect(msg)
    {:ok, state}
  end

  def on_close(state)
    :ok
  end
end
```

---

## Full Example: API Service

```winn
module UserService
  def create_user(params)
    # Validate
    token = UUID.v4()
    Logger.info("creating user", %{token: token})

    # Save to DB
    match Repo.insert(User, Map.put(:token, token, params))
      ok user =>
        jwt = JWT.sign(%{user_id: user.id}, System.get_env("JWT_SECRET"))
        {:ok, %{user: user, token: jwt}}
      err reason =>
        Logger.error("user creation failed", %{reason: reason})
        {:error, reason}
    end
  end

  def fetch_external_profile(url)
    match HTTP.get(url)
      ok resp =>
        if resp.status == 200
          {:ok, resp.body}
        else
          {:error, resp.status}
        end
      err reason =>
        {:error, reason}
    end
  end

  def notify_all(user_ids)
    Task.async_all(user_ids) do |id|
      HTTP.post("https://notify.example.com/send", %{user_id: id})
    end
  end
end
```

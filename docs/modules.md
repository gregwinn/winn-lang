# Winn Modules

Higher-level modules for building web services, APIs, and concurrent applications.

---

## HTTP Server

Built-in HTTP server powered by [Cowboy](https://github.com/ninenines/cowboy). Define routes and handlers in a Winn module.

### Defining a Router

```winn
module MyApp.Router
  use Winn.Router

  def routes()
    [
      {:get, "/", :index},
      {:get, "/users", :list_users},
      {:post, "/users", :create_user},
      {:get, "/users/:id", :get_user}
    ]
  end

  def index(conn)
    Server.json(conn, %{message: "Welcome to MyApp"})
  end

  def list_users(conn)
    match Repo.all(User)
      ok users => Server.json(conn, users)
      err reason => Server.json(conn, %{error: reason}, 500)
    end
  end

  def create_user(conn)
    params = Server.body_params(conn)
    match Repo.insert(User, params)
      ok user => Server.json(conn, user, 201)
      err reason => Server.json(conn, %{error: reason}, 422)
    end
  end

  def get_user(conn)
    id = Server.path_param(conn, "id")
    match Repo.get(User, id)
      ok user => Server.json(conn, user)
      err :not_found => Server.json(conn, %{error: "not found"}, 404)
    end
  end
end
```

### Starting the Server

```winn
Server.start(MyApp.Router, 4000)
```

Returns `{:ok, pid}`. The server listens on the given port.

### Stopping the Server

```winn
Server.stop()
```

### Response Helpers

#### `Server.json(conn, data)` / `Server.json(conn, data, status)`

Send a JSON response. Maps are automatically encoded. Default status is 200.

```winn
Server.json(conn, %{name: "Alice"})
Server.json(conn, %{error: "not found"}, 404)
```

#### `Server.text(conn, body)` / `Server.text(conn, body, status)`

Send a plain text response.

```winn
Server.text(conn, "OK")
Server.text(conn, "Created", 201)
```

#### `Server.send(conn, status, headers, body)`

Send a raw response with custom headers.

### Request Accessors

#### `Server.body_params(conn)`

Read and JSON-decode the request body. Returns a map.

```winn
params = Server.body_params(conn)
name = Map.get(:name, params)
```

#### `Server.path_param(conn, key)`

Extract a named path parameter. Routes use `:name` syntax for params.

```winn
# Route: {:get, "/users/:id", :get_user}
# Request: GET /users/42
id = Server.path_param(conn, "id")
# => "42"
```

#### `Server.query_param(conn, key)`

Extract a query string parameter.

```winn
# Request: GET /search?q=hello
q = Server.query_param(conn, "q")
# => "hello"
```

#### `Server.header(conn, name)`

Read a request header (lowercase name). Returns `nil` if not present.

```winn
auth = Server.header(conn, "authorization")
```

#### `Server.set_header(conn, name, value)`

Set a response header. Applied when the response is sent.

```winn
conn = Server.set_header(conn, "x-request-id", UUID.v4())
```

### Middleware

Define middleware functions that run before every handler. Export `middleware/0` from your router:

```winn
module Api
  use Winn.Router

  def middleware()
    [:cors, :authenticate, :log_request]
  end

  def cors(conn, next)
    conn = Server.set_header(conn, "access-control-allow-origin", "*")
    next(conn)
  end

  def authenticate(conn, next)
    match Server.header(conn, "authorization")
      nil => Server.json(conn, %{error: "unauthorized"}, 401)
      _token => next(conn)
    end
  end

  def log_request(conn, next)
    Logger.info("#{Server.method(conn)} #{Server.path(conn)}")
    next(conn)
  end
end
```

Each middleware takes `(conn, next)`. Call `next(conn)` to continue to the next middleware or handler. Return a response directly to short-circuit.

Middleware executes in list order — first in the list is outermost. Routers without `middleware/0` work unchanged.

### Route Matching

Routes are matched top-to-bottom by HTTP method and path pattern:

- Literal segments match exactly: `/users` matches `/users`
- Parameter segments start with `:` and capture the value: `/users/:id` matches `/users/42`
- Unmatched requests automatically get a 404 JSON response

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

## Auth

A small service layer over `Crypto` (password hashing), `JWT` (tokens), and `Repo`
(persistence) for email/password login. It does the register/login/current-user
dance so your handlers stay a few lines. Tokens are Bearer JWTs; the `[:auth]`
middleware (see [Middleware](#middleware)) verifies them and attaches the claims.

### User schema convention

`Auth` expects a schema named `user` (a `schema "users"` block) with at least an
`email` and a `password_hash`. `verified` and `created_at` are recommended:

```winn
module User
  use Winn.Schema

  schema "users" do
    field :email, :string
    field :password_hash, :string
    field :verified, :boolean
    field :created_at, :integer
  end
end
```

Set the JWT signing secret (and, optionally, the access-token TTL in seconds) in
config once at startup:

```winn
Config.put(:auth, :secret, System.get_env("JWT_SECRET"))
Config.put(:auth, :access_token_ttl, 3600)   # optional, default 3600
```

### `Auth.register(email, password)`

Hashes the password and inserts a user. Returns the created user **without** the
password hash. Fails with `:email_taken` if the email already exists.

```winn
match Auth.register("alice@example.com", "hunter2")
  ok user => Server.json(conn, user, 201)
  err :email_taken => Server.json(conn, %{error: "email taken"}, 409)
  err _ => Server.json(conn, %{error: "could not register"}, 422)
end
```

### `Auth.login(email, password)`

Verifies the password and, on success, returns the user plus a signed access
token. A wrong password and an unknown email both return `:invalid_credentials`
(and take similar time) so attackers can't probe which emails exist.

```winn
match Auth.login("alice@example.com", "hunter2")
  ok result => Server.json(conn, result)   # %{user: ..., access_token: "..."}
  err :invalid_credentials => Server.json(conn, %{error: "invalid login"}, 401)
end
```

### `Auth.current_user(conn)`

Resolves the authenticated user from the conn. The `[:auth]` middleware verifies
the `Authorization: Bearer <token>` header and attaches the claims; this loads the
user named by the token's `user_id`.

```winn
match Auth.current_user(conn)
  ok user => Server.json(conn, user)
  err :unauthenticated => Server.json(conn, %{error: "unauthorized"}, 401)
end
```

### Putting it together — a router

```winn
module Api.Router
  use Winn.Router

  def routes()
    [
      {:post, "/auth/register", :register},
      {:post, "/auth/login",    :login},
      {:get,  "/api/me",        :me}
    ]
  end

  def middleware()
    [:cors, :auth]
  end

  def auth_config()
    %{secret: Config.get(:auth, :secret), exclude: ["/auth/login", "/auth/register"]}
  end

  def register(conn)
    params = Server.body_params(conn)
    match Auth.register(params.email, params.password)
      ok user => Server.json(conn, user, 201)
      err reason => Server.json(conn, %{error: reason}, 422)
    end
  end

  def login(conn)
    params = Server.body_params(conn)
    match Auth.login(params.email, params.password)
      ok result => Server.json(conn, result)
      err _ => Server.json(conn, %{error: "invalid login"}, 401)
    end
  end

  def me(conn)
    match Auth.current_user(conn)
      ok user => Server.json(conn, user)
      err _ => Server.json(conn, %{error: "unauthorized"}, 401)
    end
  end
end
```

A JS frontend logs in, then sends the token on protected requests:

```js
const { access_token } = await (await fetch("/auth/login", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ email, password }),
})).json();

await fetch("/api/me", { headers: { Authorization: `Bearer ${access_token}` } });
```

> Refresh tokens, logout/revocation, and cookie sessions build on this in later
> releases. This is the core access-token flow.

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

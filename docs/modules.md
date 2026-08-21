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

#### `Server.set_cookie(conn, name, value)` / `Server.set_cookie(conn, name, value, opts)`

Set a response cookie. `opts` keys: `http_only`, `secure` (booleans), `same_site`
(`"Lax"` / `"Strict"` / `"None"`), `path`, `domain`, `max_age` (seconds). Multiple
cookies are supported.

```winn
conn = Server.set_cookie(conn, "session", token, %{
  http_only: true, secure: true, same_site: "Lax", path: "/"
})
```

#### `Server.get_cookie(conn, name)`

Read a request cookie by name. Returns the value, or `nil`.

```winn
token = Server.get_cookie(conn, "session")
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

### Timeouts & options

Every verb takes an optional trailing **options map**. Defaults are generous (connect 15s, receive 30s) and overridable per request — useful for slow "compute on request" endpoints that exceed hackney's old 5s receive default.

```winn
HTTP.get(url, %{timeout: 30000})                 # receive timeout (ms)
HTTP.post(url, body, %{connect_timeout: 15000})  # connect timeout (ms)
HTTP.post(url, body, %{follow_redirect: false})
```

Recognised keys: `timeout` / `recv_timeout` (receive timeout in ms — `timeout` is an alias), `connect_timeout` (ms), and `follow_redirect` (boolean). The no-option forms (`HTTP.get(url)`, `HTTP.post(url, body)`, …) use the defaults, so existing code is unchanged.

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

### Schema conventions

`Auth` expects a `user` schema (a `schema "users"` block) with at least an `email`
and a `password_hash`, plus an `auth_token` schema (`schema "auth_tokens"`) that
backs refresh tokens:

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

module AuthToken
  use Winn.Schema

  schema "auth_tokens" do
    field :user_id, :integer
    field :token_hash, :string
    field :purpose, :string      # refresh | verify_email | reset_password
    field :expires_at, :integer
    field :created_at, :integer
  end
end
```

The one `auth_tokens` table backs refresh tokens **and** the single-use
verification / password-reset tokens (`purpose` distinguishes them).

Migration for the token table:

```winn
module Migrations.CreateAuthTokens
  def up()
    Repo.execute("CREATE TABLE auth_tokens (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL,
      token_hash TEXT NOT NULL UNIQUE,
      purpose TEXT NOT NULL,
      expires_at BIGINT NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    )")
  end

  def down()
    Repo.execute("DROP TABLE auth_tokens")
  end
end
```

Set the JWT signing secret and (optionally) the token TTLs in config at startup:

```winn
Config.put(:auth, :secret, System.get_env("JWT_SECRET"))
Config.put(:auth, :access_token_ttl, 3600)      # optional, default 3600 (1h)
Config.put(:auth, :refresh_token_ttl, 2592000)  # optional, default 30 days
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

Verifies the password and, on success, returns the user plus a short-lived
**access token** (JWT) and a long-lived **refresh token**. A wrong password and an
unknown email both return `:invalid_credentials` (and take similar time) so
attackers can't probe which emails exist.

```winn
match Auth.login("alice@example.com", "hunter2")
  ok result => Server.json(conn, result)
  # result => %{user: ..., access_token: "...", refresh_token: "..."}
  err :invalid_credentials => Server.json(conn, %{error: "invalid login"}, 401)
end
```

The access token is stateless and short-lived; the refresh token is opaque,
stored server-side (only its hash), and revocable.

### `Auth.refresh(refresh_token)`

Exchanges a valid refresh token for a new access token **and a rotated refresh
token** — the presented token is single-use and stops working after this call. An
expired, unknown, or already-rotated token returns `:invalid_token`.

```winn
match Auth.refresh(params.refresh_token)
  ok tokens => Server.json(conn, tokens)
  # tokens => %{access_token: "...", refresh_token: "..."}
  err :invalid_token => Server.json(conn, %{error: "invalid refresh token"}, 401)
end
```

### `Auth.logout(refresh_token)`

Revokes a refresh token (deletes it server-side). Idempotent — always returns `:ok`.

```winn
Auth.logout(params.refresh_token)
Server.json(conn, %{status: "ok"})
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

### Account recovery — email verification & password reset

These use single-use, hashed, expiring tokens (stored in `auth_tokens`) delivered by
the [`Mailer`](stdlib.md#mailer). Configure the email + link settings once:

```winn
Config.put(:auth, :verify_email, true)   # register/2 then emails a verification link
Config.put(:auth, :verify_url, "https://myapp.com/auth/verify?token=")
Config.put(:auth, :reset_url,  "https://myapp.com/auth/reset?token=")
# optional TTLs (seconds): verify_token_ttl (default 24h), reset_token_ttl (default 1h)
```

#### `Auth.verify_email(token)`

Consume a verification token and mark the user verified. The token is single-use;
expired/unknown/reused tokens return `:invalid_token`.

```winn
# GET /auth/verify?token=...
match Auth.verify_email(Server.query_param(conn, "token"))
  ok user => Server.json(conn, %{verified: true})
  err _ => Server.json(conn, %{error: "invalid or expired token"}, 400)
end
```

`Auth.request_email_verification(email)` re-sends a link (always `:ok`).

#### `Auth.request_password_reset(email)`

Email a reset link if the address exists. **Always returns `:ok`** — it never reveals
whether an email is registered.

```winn
def forgot(conn)
  Auth.request_password_reset(Server.body_params(conn).email)
  Server.json(conn, %{status: "ok"})   # same response either way
end
```

#### `Auth.reset_password(token, new_password)`

Set a new password using a valid reset token (single-use; expired/unknown → `:invalid_token`).

```winn
def reset(conn)
  params = Server.body_params(conn)
  match Auth.reset_password(params.token, params.password)
    ok _ => Server.json(conn, %{status: "ok"})
    err _ => Server.json(conn, %{error: "invalid or expired token"}, 400)
  end
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
      {:post, "/auth/refresh",  :refresh},
      {:post, "/auth/logout",   :logout},
      {:get,  "/auth/verify",   :verify},
      {:post, "/auth/forgot",   :forgot},
      {:post, "/auth/reset",    :reset},
      {:get,  "/api/me",        :me}
    ]
  end

  def middleware()
    [:cors, :auth]
  end

  def auth_config()
    %{
      secret: Config.get(:auth, :secret),
      exclude: ["/auth/login", "/auth/register", "/auth/refresh",
                "/auth/verify", "/auth/forgot", "/auth/reset"]
    }
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

  def refresh(conn)
    params = Server.body_params(conn)
    match Auth.refresh(params.refresh_token)
      ok tokens => Server.json(conn, tokens)
      err _ => Server.json(conn, %{error: "invalid refresh token"}, 401)
    end
  end

  def logout(conn)
    params = Server.body_params(conn)
    Auth.logout(params.refresh_token)
    Server.json(conn, %{status: "ok"})
  end

  def verify(conn)
    match Auth.verify_email(Server.query_param(conn, "token"))
      ok _ => Server.json(conn, %{verified: true})
      err _ => Server.json(conn, %{error: "invalid or expired token"}, 400)
    end
  end

  def forgot(conn)
    Auth.request_password_reset(Server.body_params(conn).email)
    Server.json(conn, %{status: "ok"})   # always 200 — no user enumeration
  end

  def reset(conn)
    params = Server.body_params(conn)
    match Auth.reset_password(params.token, params.password)
      ok _ => Server.json(conn, %{status: "ok"})
      err _ => Server.json(conn, %{error: "invalid or expired token"}, 400)
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

A JS frontend logs in, calls protected endpoints with the access token, and
silently refreshes when it expires:

```js
let { access_token, refresh_token } = await (await fetch("/auth/login", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ email, password }),
})).json();

let res = await fetch("/api/me", {
  headers: { Authorization: `Bearer ${access_token}` },
});

if (res.status === 401) {
  // access token expired — rotate and retry
  ({ access_token, refresh_token } = await (await fetch("/auth/refresh", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token }),
  })).json());
}

// on sign-out:
await fetch("/auth/logout", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ refresh_token }),
});
```

### Cookie sessions & CSRF

The examples above use **Bearer tokens** (the default) — the frontend stores the
access token and sends it in the `Authorization` header. For same-origin web apps
you can instead keep the token out of JavaScript entirely by setting
`strategy: :cookie` in `auth_config`:

```winn
def auth_config()
  %{strategy: :cookie, secret: Config.get(:auth, :secret),
    exclude: ["/auth/login", "/auth/register", "/auth/refresh"]}
end
```

In cookie mode the `[:auth]` middleware reads the access JWT from an **HttpOnly**
cookie instead of the header, and enforces **double-submit CSRF** on unsafe methods
(POST/PUT/PATCH/DELETE): the request must carry an `X-CSRF-Token` header equal to the
non-HttpOnly `csrf` cookie. Your login/refresh handlers set the cookies with
`Auth.write_session`, and logout clears them with `Auth.clear_session`:

```winn
def login(conn)
  params = Server.body_params(conn)
  match Auth.login(params.email, params.password)
    ok tokens =>
      conn = Auth.write_session(conn, tokens)   # sets access/refresh (HttpOnly) + csrf cookies
      Server.json(conn, %{status: "ok"})
    err _ => Server.json(conn, %{error: "invalid login"}, 401)
  end
end

def logout(conn)
  conn = Auth.clear_session(conn)
  Server.json(conn, %{status: "ok"})
end
```

The browser sends the cookies automatically. The frontend reads the `csrf` cookie and
echoes it on writes:

```js
function csrf() {
  return document.cookie.split("; ").find(c => c.startsWith("csrf="))?.split("=")[1];
}
await fetch("/api/posts", {
  method: "POST",
  headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf() },
  body: JSON.stringify(post),   // access-token cookie sent automatically
});
```

> **Cross-origin cookie auth** (SPA on a different origin than the API) additionally
> needs CORS credentials: set `cors_config` `credentials: true` and a **specific**
> `origins` (not `*`), and the frontend must send `fetch(..., { credentials: "include" })`.
> Same-origin apps don't need CORS at all.

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

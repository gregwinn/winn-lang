# Winn Roadmap

Each chunk below is independently buildable — there are no hard ordering requirements unless noted under **Depends on**.

---

## Language Features (Compiler Changes)

These all touch `winn_lexer.xrl`, `winn_parser.yrl`, `winn_transform.erl`, and `winn_codegen.erl`.

---

### L1 — if/else

**Goal:** `if/else` as a first-class expression.

**Syntax:**
```winn
if x > 0
  IO.puts("positive")
else
  IO.puts("non-positive")
end

result = if user != nil
  user.name
else
  "anonymous"
end
```

**Implementation:**
- Lexer: add `if`, `else` tokens (check if already present)
- Parser: `if_expr -> 'if' expr expr_seq 'else' expr_seq 'end'` and `if_expr -> 'if' expr expr_seq 'end'` (no else)
- Transform: `{if_expr, Line, Cond, Then, Else}` → `{case_expr, Line, Cond, [true_clause, false_clause]}`
- Codegen: handled by existing `gen_expr({case_expr,...})`

**Tests:** `winn_l1_tests.erl` — parse, transform, end-to-end (if true, if false, if/else, if as expression)

---

### L2 — switch expression

**Goal:** Multi-branch value matching without `ok`/`err` sugar.

**Syntax:**
```winn
switch status
  :active   => "Active"
  :inactive => "Inactive"
  _         => "Unknown"
end
```

**Implementation:**
- Lexer: add `switch` token
- Parser: `switch_expr -> 'switch' expr switch_clauses 'end'`; `switch_clause -> expr '=>' expr_seq`
- Transform: desugar to `{case_expr, Line, Scrutinee, Clauses}` — each clause becomes `{case_clause, Line, [Pattern], none, Body}`
- Codegen: handled by existing case codegen

**Tests:** `winn_l2_tests.erl`

---

### L3 — Guards

**Goal:** `when` guards on function clauses and match/switch clauses.

**Syntax:**
```winn
def divide(a, b) when b != 0
  a / b
end

def divide(_, 0)
  {:error, "division by zero"}
end
```

```winn
switch value
  n when n > 0 => "positive"
  n when n < 0 => "negative"
  _            => "zero"
end
```

**Implementation:**
- Lexer: add `when` token
- Parser: extend `function_def` to accept optional `'when' expr` guard; extend case/switch clauses similarly
- Transform: pass guard expression through; `wrap_in_case` must carry guard into `case_clause`
- Codegen: `gen_case_clause` currently hardcodes `cerl:c_atom(true)` as guard — replace with `gen_expr(Guard)` when guard is present

**Tests:** `winn_l3_tests.erl`

---

### L4 — try/rescue/after

**Goal:** Exception handling.

**Syntax:**
```winn
try
  risky_operation()
rescue
  {:error, reason} => IO.puts("caught: " <> reason)
  _                => IO.puts("unknown error")
after
  cleanup()
end
```

**Implementation:**
- Lexer: add `try`, `rescue`, `after` tokens
- Parser: `try_expr -> 'try' expr_seq rescue_clauses after_clause 'end'`
- Transform: `{try_expr, Line, Body, RescueClauses, After}` → Core Erlang `cerl:c_try/5`
- Codegen: `gen_expr({try_expr,...})` → `cerl:c_try(Body, [Var], Handler, [Var], AfterBody)` where handler is a case over the caught value

**Tests:** `winn_l4_tests.erl`

---

## Runtime Additions (No Compiler Changes)

These only require adding functions to `winn_runtime.erl` (exports + implementations) and updating `resolve_dot_call` in `winn_codegen.erl`.

---

### R1 — Environment Variables

**Goal:** Read and write OS environment variables.

**Syntax:**
```winn
port = System.get_env("PORT")
# => "4000" or nil

System.get_env("PORT", "3000")   # with default
System.put_env("DEBUG", "true")
```

**Implementation:**
- Add `'system.get_env'/1`, `'system.get_env'/2`, `'system.put_env'/2` to `winn_runtime.erl`
- `os:getenv/1` returns `false` for missing — normalize to `nil`
- Add `resolve_dot_call('System', Fun) -> {winn_runtime, ...}` in codegen

**Tests:** `winn_r1_tests.erl`

---

### R2 — UUID

**Goal:** Generate UUIDs.

**Syntax:**
```winn
id = UUID.v4()
# => "550e8400-e29b-41d4-a716-446655440000"
```

**Implementation:**
- Add dep `{uuid, "2.0.6"}` to `rebar.config` (or implement v4 directly using `crypto:strong_rand_bytes/16`)
- Add `'uuid.v4'/0` to `winn_runtime.erl`
- Add `resolve_dot_call('UUID', Fun)` in codegen

**Tests:** `winn_r2_tests.erl` — verify format matches UUID v4 regex

---

### R3 — DateTime

**Goal:** Working with dates and times.

**Syntax:**
```winn
now  = DateTime.now()              # Unix timestamp (integer seconds)
iso  = DateTime.to_iso8601(now)    # "2026-03-27T12:00:00Z"
ts   = DateTime.from_iso8601(iso)
diff = DateTime.diff(ts1, ts2)     # seconds between two timestamps
DateTime.format(now, "%Y-%m-%d")
```

**Implementation:**
- Add `'datetime.now'/0`, `'datetime.to_iso8601'/1`, `'datetime.from_iso8601'/1`, `'datetime.diff'/2`, `'datetime.format'/2` to `winn_runtime.erl`
- Use Erlang `calendar` and `os:system_time/1` builtins — no extra dep needed
- Add `resolve_dot_call('DateTime', Fun)` in codegen

**Tests:** `winn_r3_tests.erl`

---

### R4 — Structured Logging

**Goal:** Levelled JSON-structured logging.

**Syntax:**
```winn
Logger.info("user created", %{user_id: id})
Logger.warn("slow query", %{duration_ms: 450})
Logger.error("db connection failed", %{reason: reason})
Logger.debug("checkpoint", %{step: 3})
```

**Implementation:**
- Add `winn_logger.erl` (new module) — formats `{level, message, metadata}` as JSON line to stderr/stdout
- Add `resolve_dot_call('Logger', Fun) -> {winn_logger, Fun}` in codegen
- Use Erlang's built-in `logger` application as the backend (OTP 21+)

**Tests:** `winn_r4_tests.erl` — verify log output format

---

### R5 — Crypto / Hashing

**Goal:** Password hashing and general crypto.

**Syntax:**
```winn
hash   = Crypto.hash(:sha256, "data")
hmac   = Crypto.hmac(:sha256, "secret", "data")
token  = Crypto.random_bytes(32)
encoded = Crypto.base64_encode(token)
decoded = Crypto.base64_decode(encoded)

# Password hashing (bcrypt)
hashed = Crypto.hash_password("mysecret")
true   = Crypto.verify_password("mysecret", hashed)
```

**Implementation:**
- Add `winn_crypto.erl` — wraps `crypto` OTP app + add `bcrypt` dep (`{bcrypt, "1.1.3"}`)
- Add `resolve_dot_call('Crypto', Fun) -> {winn_crypto, Fun}` in codegen

**Depends on:** Nothing

**Tests:** `winn_r5_tests.erl`

---

## New Modules

---

### M1 — HTTP Client

**Goal:** Make HTTP requests to external APIs with JSON built-in.

**Syntax:**
```winn
# GET
{:ok, resp} = HTTP.get("https://api.example.com/users")

# POST with JSON body
{:ok, resp} = HTTP.post("https://api.example.com/users", %{
  name: "Alice",
  email: "alice@example.com"
})

# Access response
resp.status   # 200
resp.body     # decoded map (if Content-Type is application/json)
resp.headers  # map of headers
```

**Implementation:**
- Add dep `{hackney, "1.20.1"}` and `{jsone, "1.8.1"}` to `rebar.config`
- Create `winn_http.erl` with `get/1`, `post/2`, `put/2`, `patch/2`, `delete/1`, `request/3`
- Automatically encode map bodies to JSON, decode JSON responses
- Response is a map `#{status, body, headers}`
- Add `resolve_dot_call('HTTP', Fun) -> {winn_http, Fun}` in codegen

**Tests:** `winn_m1_tests.erl` — mock HTTP or test against httpbin.org

---

### M2 — Config System

**Goal:** Environment-specific config files.

**File structure:**
```
config/
├── config.winn       # shared config
├── dev.winn          # development overrides
├── prod.winn         # production overrides
└── test.winn         # test overrides
```

**config/config.winn:**
```winn
config :database,
  pool_size: 10,
  timeout: 5000

config :http,
  port: 4000
```

**Syntax in code:**
```winn
port   = Config.get(:http, :port)           # 4000
dbsize = Config.get(:database, :pool_size)  # 10
Config.get(:http, :port, 3000)              # with default
```

**Implementation:**
- Add `config` keyword to lexer/parser — `config :key, key: val, key: val`
- Create `winn_config.erl` — reads and parses config files at app start, stores in ETS
- `WINN_ENV` env var selects config overlay (`dev`, `prod`, `test`)
- Add `resolve_dot_call('Config', Fun) -> {winn_config, Fun}` in codegen

**Tests:** `winn_m2_tests.erl`

---

### M3 — Application Startup

**Goal:** Define an OTP application entry point with a supervision tree.

**Syntax:**
```winn
module MyApp
  use Winn.Application

  def start(_type, _args)
    children = [
      {Counter, [0]},
      {MyApp.Repo, []}
    ]
    Supervisor.start_link(children, %{strategy: :one_for_one})
  end
end
```

**Implementation:**
- `use Winn.Application` → adds `-behaviour(application).` attribute
- Generates `start/2` wrapper if not defined
- Update `winn.app.src` to set `mod: {myapp, []}` (needs CLI integration)
- Add `expand_use` clause for `'Winn', 'Application'` in `winn_transform.erl`

**Depends on:** Works best alongside M2 (Config)

**Tests:** `winn_m3_tests.erl`

---

### M4 — Task / Async

**Goal:** Run work concurrently without writing raw GenServer code.

**Syntax:**
```winn
# Fire and forget
Task.spawn(fn => heavy_computation())

# Async + await
task   = Task.async(fn => fetch_user(id))
result = Task.await(task)           # blocks until done
result = Task.await(task, 5000)     # with timeout (ms)

# Parallel map
results = Task.async_all([1, 2, 3]) do |n|
  fetch_user(n)
end
```

**Implementation:**
- Create `winn_task.erl` wrapping Erlang `spawn`/`receive` and message passing
- `Task.async` spawns a process, returns a ref; `Task.await` blocks on the ref
- `Task.async_all` spawns N processes, collects all results
- Add `resolve_dot_call('Task', Fun) -> {winn_task, Fun}` in codegen

**Tests:** `winn_m4_tests.erl`

---

### M5 — JWT

**Goal:** Sign and verify JSON Web Tokens for service-to-service auth.

**Syntax:**
```winn
secret  = System.get_env("JWT_SECRET")
token   = JWT.sign(%{user_id: 42, role: :admin}, secret)

match JWT.verify(token, secret)
  ok claims => claims.user_id
  err reason => {:error, :unauthorized}
end
```

**Implementation:**
- Add dep `{joken, "2.6.2"}` (Erlang JWT library) to `rebar.config`
- Create `winn_jwt.erl` wrapping joken for HS256 sign/verify
- Add `resolve_dot_call('JWT', Fun) -> {winn_jwt, Fun}` in codegen

**Depends on:** R1 (env vars) recommended for secret management

**Tests:** `winn_m5_tests.erl` — sign, verify, expired token, tampered token

---

### M6 — WebSockets

**Goal:** WebSocket client for connecting to external services and a server handler for accepting connections.

**Client syntax:**
```winn
{:ok, conn} = WS.connect("wss://api.example.com/ws")
WS.send(conn, %{type: :subscribe, channel: "prices"})

match WS.recv(conn)
  ok msg  => IO.inspect(msg)
  err reason => IO.puts("disconnected")
end

WS.close(conn)
```

**Server handler syntax:**
```winn
module MyApp.WsHandler
  use Winn.WebSocket

  def on_connect(conn)
    {:ok, %{conn: conn, subs: []}}
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

**Implementation:**
- Add dep `{gun, "2.1.0"}` to `rebar.config` (WebSocket client)
- Create `winn_ws.erl` — client: `connect/1`, `send/2`, `recv/1`, `close/1`
- Create `winn_ws_handler.erl` — server behaviour wrapper (requires Cowboy if serving)
- `use Winn.WebSocket` adds `-behaviour(winn_ws_handler)` and callback stubs
- Add `resolve_dot_call('WS', Fun) -> {winn_ws, Fun}` in codegen

**Tests:** `winn_m6_tests.erl` — client against echo.websocket.org or local mock

---

### C1 — CLI Task System

**Goal:** Define and run project tasks from the CLI, similar to Mix tasks.

**Syntax:**
```sh
winn task.run db.migrate
winn task.run db.seed
winn task.run routes
```

**Task definition in Winn:**
```winn
module Tasks.Db.Migrate
  use Winn.Task

  def run(args)
    IO.puts("Running migrations...")
  end
end
```

**Implementation:**
- Add `use Winn.Task` directive (transform: adds `-behaviour(winn_task)`)
- Update CLI (`winn_cli.erl`) to handle `task.run <name>` subcommand
- CLI discovers task modules by scanning compiled `.beam` files for `-behaviour(winn_task)`
- Built-in tasks: `db.migrate`, `db.rollback`, `db.seed` (stubs that call `winn_repo` migration helpers)
- Add migration file runner to `winn_repo.erl`

**Depends on:** M3 (Application) recommended; M2 (Config) for DB config

**Tests:** `winn_c1_tests.erl`

---

## Medium Impact — Quality of Life (Planned)

---

### MI1 — HTTP Middleware System

**Goal:** Before/after hooks for HTTP request processing — auth, CORS, logging, etc.

**Syntax:**
```winn
module MyApp.Router
  use Winn.Router

  def middleware()
    [:log_request, :cors, :authenticate]
  end

  def log_request(conn, next)
    Logger.info("#{Server.method(conn)} #{Server.path(conn)}")
    next(conn)
  end

  def cors(conn, next)
    conn = Server.set_header(conn, "access-control-allow-origin", "*")
    next(conn)
  end

  def authenticate(conn, next)
    match Server.header(conn, "authorization")
      nil => Server.json(conn, %{error: "unauthorized"}, 401)
      token => next(conn)
    end
  end
end
```

**Implementation:**
- Add `middleware/0` callback to router convention (returns list of function name atoms)
- In `winn_router.erl` `init/2`: after matching route, chain middleware fns before calling handler
- Each middleware receives `(conn, next_fn)` where `next_fn` is a closure over the remaining chain
- Add `Server.set_header/3` to `winn_server.erl`
- No lexer/parser changes needed

**Tests:** `winn_mi1_tests.erl` — middleware ordering, short-circuit (auth fail), header injection

---

### MI2 — to_string / to_integer Callable from Winn

**Goal:** Make type conversion functions directly callable without module prefix.

**Syntax:**
```winn
to_string(42)        # => "42"
to_integer("42")     # => 42
to_float("3.14")     # => 3.14
to_atom("hello")     # => :hello
```

**Implementation:**
- In `winn_codegen.erl` `gen_expr({call, _, Fun, Args})`: check if `Fun` is one of `to_string`, `to_integer`, `to_float`, `to_atom`
- If so, emit `cerl:c_call(cerl:c_atom(winn_runtime), cerl:c_atom(Fun), Args)` instead of `cerl:c_apply`
- No lexer/parser/transform changes needed — just a codegen special case

**Tests:** `winn_mi2_tests.erl` — e2e compile `to_string(42)`, `to_integer("5")`, etc.

---

### MI3 — Range Literals

**Goal:** `1..10` syntax for generating integer sequences.

**Syntax:**
```winn
1..5             # => [1, 2, 3, 4, 5]
for i in 1..10 do
  IO.puts(to_string(i))
end
```

**Implementation:**
- Lexer: add `..` two-character operator token (before single `.` rule)
- Parser: `range_expr -> expr '..' expr` producing `{range, Line, From, To}`
- Transform: pass through
- Codegen: `gen_expr({range,...})` → `cerl:c_call(cerl:c_atom(lists), cerl:c_atom(seq), [From, To])`
- Alternatively, add `Range.new/2` to `winn_runtime.erl` for step support later

**Tests:** `winn_mi3_tests.erl` — `1..5`, `5..1` (empty or reverse?), `for x in 1..3`

---

### MI4 — Multi-line Switch/Rescue Bodies

**Goal:** Allow multiple expressions in switch clause and rescue clause bodies.

**Current limitation:** Switch/rescue clause bodies are single expressions due to parser ambiguity (no newline tokens).

**Syntax (desired):**
```winn
switch status
  :active =>
    Logger.info("active")
    :ok
  :inactive =>
    Logger.warn("inactive")
    :disabled
end
```

**Implementation options:**

**Option A: Add significant newlines.** Add a newline token emitted by the lexer when not inside `()`, `[]`, `{}`. Use it as a clause body terminator. This is the cleanest long-term solution but requires reworking the lexer's whitespace handling (add a depth counter for brackets).

**Option B: Use `do...end` for multi-line bodies.**
```winn
switch status
  :active => do
    Logger.info("active")
    :ok
  end
  :inactive => do
    Logger.warn("inactive")
    :disabled
  end
end
```

**Option C: Require explicit `begin...end` blocks.** Similar to B but different keyword.

**Recommended:** Option A (significant newlines) for the best developer experience, but it's a larger change. Option B is a pragmatic interim solution.

**Tests:** `winn_mi4_tests.erl` — multi-expression switch/rescue bodies

---

### MI5 — Better Compiler Error Messages

**Goal:** Human-readable errors with source file, line number, and context.

**Current state:** Errors are raw Erlang tuples (`{error, {Line, winn_parser, [...]}}`) with no source context.

**Syntax (desired output):**
```
error: unexpected token 'end'
  --> src/app.winn:15:3
   |
15 |   end
   |   ^^^ expected expression
```

**Implementation:**
- Create `winn_errors.erl` module with `format_error/2` (takes error tuple + source string)
- Lexer errors: `{Line, winn_lexer, {illegal, Char}}` → "illegal character `X` at line N"
- Parser errors: `{Line, winn_parser, Msg}` → "syntax error at line N: ..."
- Core lint errors: extract from `compile:forms` error tuples
- Add source line context by splitting source on newlines and showing the relevant line
- Integrate into `winn.erl` `compile_file/2` and `winn_cli.erl` error paths
- Color output (ANSI codes) when outputting to terminal

**Tests:** `winn_mi5_tests.erl` — verify error message format for known bad inputs

---

## Build Order Suggestions

**If building for a service that calls external APIs:**
→ R1 (env vars) → M1 (HTTP client) → M5 (JWT) → R4 (logging)

**If building a data-heavy service:**
→ R1 (env vars) → M2 (config) → M3 (application) → C1 (tasks/migrations)

**If adding language expressiveness first:**
→ L1 (if/else) → L2 (switch) → L3 (guards) → L4 (try/rescue)

**If building a real-time service:**
→ M4 (tasks) → M6 (websockets) → R4 (logging)

---

## Status

| Chunk | Description | Status |
|-------|-------------|--------|
| L1 | if/else | done |
| L2 | switch | done |
| L3 | guards (when) | done |
| L4 | try/rescue | done |
| R1 | env vars | done |
| R2 | UUID | done |
| R3 | DateTime | done |
| R4 | structured logging | done |
| R5 | crypto/hashing | done |
| M1 | HTTP client | done |
| M2 | config system | done |
| M3 | application startup | done |
| M4 | task/async | done |
| M5 | JWT | done |
| M6 | WebSockets | done |
| C1 | CLI task runner | planned |
| HI1 | String interpolation | done |
| HI2 | Map field access | done |
| HI3 | Standalone lambdas | done |
| HI4 | Pattern assignment | done |
| HI5 | JSON module | done |
| HI6 | for comprehensions | done |
| S1 | HTTP server (Cowboy) | done |
| MI1 | Middleware system | planned |
| MI2 | to_string/to_integer from Winn | planned |
| MI3 | Range literals (1..10) | planned |
| MI4 | Multi-line switch/rescue bodies | planned |
| MI5 | Better compiler error messages | planned |

# Changelog

All notable changes to the Winn language are documented here.

## [Unreleased]

### Breaking Changes
- **Chained comparisons are now a parse error** — `a < b < c`, `a == b == c`, etc. used to parse silently as `(a < b) < c` (comparing a bool against a number). They now produce a parse error. The comparison rules in `winn_parser.yrl` were tightened from `cmp_expr -> cmp_expr OP add_expr` (left-recursive, allowing chains) to `cmp_expr -> add_expr OP add_expr` (one comparison only). No `.winn` source in the repo or any winn-* package used this pattern. (#98)
- **`List.first/1` and `List.last/1` return `nil` on empty lists** — previously returned the atom `:not_found`. Callers matching on `:not_found` must switch to `nil` (or `case` on both during migration). The new return type aligns with Map.get and field access for a single "missing" sentinel across the stdlib. (#58)

### Fixed
- **Repeated `_` wildcard in a function head or pattern now compiles** ([#170](https://github.com/gregwinn/winn-lang/issues/170)) — codegen emitted the literal Core Erlang variable `'_'` for every wildcard, so any head/pattern with more than one (e.g. `def head_or([x | _], _)`) was rejected by `core_lint` with `{duplicate_var,'_',...}`. Each `_` is now freshened to a distinct anonymous variable in `winn_codegen_pattern.erl`. Also shipped as the 0.9.3 hotfix off the release line.
- **`Repo.insert`/`get`/`get_by`/`update` returned misaligned records** — these mapped the result row against the schema's declared field list, which omits the DB-managed `id`. Because `RETURNING *` / `SELECT *` return `id` as the first column, every value landed under the wrong key and the final column was dropped (e.g. `%{email: 1, password_hash: "a@b.com"}` with no `id`), silently corrupting any read/write round-trip. They now map via the result-set column metadata (`row_to_map_cols/2`, already used by `Repo.all`), so returned records include `id` and are correctly keyed. The buggy `row_to_map/2` helper was removed. (#172)

### Compiler
- **Parser shift/reduce conflicts: 53 → 3** — Added explicit `Left`/`Nonassoc` precedence declarations to `winn_parser.yrl` for every operator (`|>`, `|>=`, `or`, `and`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `+`, `-`, `<>`, `..`, `*`, `/`). yecc auto-resolves 50 of the 53 historical conflicts. The 3 remaining are intentional "longest-match wins" structural cases (`foo() do end` binding the block to the call, `ident(args)` being a call rather than a var followed by parens, and the same for `a.b(args)`) and are now documented inline next to the relevant rules. The formatter's hardcoded precedence ladder in `winn_formatter.erl` was extended to cover `..` and `|>=` to stay aligned with the parser. (#98)

### Language
- **`pipeline` keyword** — Broadway-shape supervised multi-stage dataflow. Declare a `producer`, one `processor` (with configurable `concurrency`, `retry`, and per-message `timeout`), and an optional `batcher` (size + timeout flushing). Compiles to a supervisor tree with prefetch-driven backpressure, graceful drain on shutdown, and metrics published through the `Metrics` module. User-written producer modules implement a four-callback behaviour (`init/1`, `pull/2`, `ack/3`, `terminate/2`). See [docs/otp.md](docs/otp.md#pipeline). VS Code grammar update for `pipeline`, `producer`, `processor`, and `batcher` keywords will follow in a separate `language-winn-vscode` release. (#104)
- **`private def`** — module-private functions. Functions declared with `private def name(...)` are callable from within the same module but excluded from the module's export list, so cross-module calls raise `undef`. Mirrors the existing `async def` modifier-before-`def` style. Multi-clause and guarded variants both supported. (#128)
- **String escape sequences** — double-quoted strings now support `\"`, `\\`, `\n`, `\r`, `\t`, and `\0`. The lexer rule was widened from `\"[^\"]*\"` to `\"(\\.|[^\"\\])*\"`, and the formatter's symmetric `escape_string/1` re-emits the same escapes so `winn fmt` round-trips them. Unknown escapes (e.g. `\q`) pass through literally. Unblocks hand-writing Prometheus exposition format, JSON-by-hand, CSV with embedded quotes, and templated HTML attributes — previously these had to be written in Erlang. Triple-quoted strings are unchanged. (#157)

### Developer Tooling
- **`winn create auth` — scaffold a complete email/password setup** (#168). Generates `User` + `AuthToken` schemas, the `users` / `auth_tokens` migrations (ordered, with constraints), and an `AuthController` router wiring all eight endpoints (register / login / refresh / logout / verify / forgot / reset / me) with `[:cors, :auth]` middleware and an `exclude` list. New [docs/auth.md](docs/auth.md) end-to-end guide (token model, Bearer vs cookie, account recovery, a runnable JS frontend example); `docs/cli.md` + roadmap updated. Also fixed `%{ok: true}` examples in `docs/modules.md` (`ok`/`err` are reserved and can't be map keys → use `%{status: "ok"}`). (#168)

### Stdlib
- **`Auth` account recovery — email verification + password reset** (#167). `Auth.verify_email/1`, `Auth.request_email_verification/1`, `Auth.request_password_reset/1`, `Auth.reset_password/2`. Uses single-use, hashed, expiring tokens (stored in the same `auth_tokens` table with a new `purpose` column — `refresh` / `verify_email` / `reset_password`) delivered via `Mailer` (#166). `request_password_reset` always returns `:ok` (no user enumeration); reset/verify tokens are single-use and purpose-checked, so a recovery link can't be redeemed at `/auth/refresh`. `register/2` emails a verification link when `auth.verify_email` is set. New config: `auth.verify_email`, `auth.verify_url` / `auth.reset_url` (link prefixes), `auth.verify_token_ttl` (default 24h) / `auth.reset_token_ttl` (default 1h). The `auth_token` schema + migration gain a `purpose` field. See [docs/modules.md](docs/modules.md#account-recovery--email-verification--password-reset). (#167)
- **`Mailer` — pluggable email delivery** (`Mailer.send/3,4`). Transport chosen via `Config` (`mailer.transport`): `:http` posts to SendGrid's v3 API (set `mailer.api_key` / `mailer.from`; uses `hackney` directly since `winn_http` doesn't expose request headers — no new deps), and `:test` captures messages in-process (`Mailer.captured/0` / `Mailer.clear/0`) so flows are assertable without sending real mail. `opts` support `from`, `reply_to`, and `html`. SMTP is intentionally deferred (it would add a dependency). `Mailer` maps to `winn_mailer` in `winn_codegen_resolve`. Prerequisite for account recovery (#167). See [docs/stdlib.md](docs/stdlib.md#mailer). (#166)
- **`Auth` cookie sessions + CSRF + configurable strategy** (#165). The `[:auth]` middleware now supports `auth_config` `strategy: :cookie` in addition to the default `:bearer`. In cookie mode it reads the access JWT from an **HttpOnly** cookie (stateless — same JWT, no server-side session store) and enforces **double-submit CSRF** on unsafe methods (`X-CSRF-Token` header must equal the `csrf` cookie). New `Auth.write_session(conn, tokens)` / `Auth.clear_session(conn)` set/clear the cookies on login/logout, and `Server.set_cookie/3,4` + `Server.get_cookie/2` expose cookies to handlers. `winn_cors` gains a `credentials` option (emits `Access-Control-Allow-Credentials: true`) for cross-origin cookie auth. Bearer remains the default — no change for existing apps. See [docs/modules.md](docs/modules.md#cookie-sessions--csrf). (#165)
- **`Auth` refresh tokens + revocation** (`Auth.refresh/1`, `Auth.logout/1`). `Auth.login` now also issues a long-lived **refresh token** alongside the short-lived access JWT, returning `%{user, access_token, refresh_token}`. The refresh token is an opaque high-entropy random string; only its SHA-256 hash is stored (in an `auth_tokens` table), so a DB leak doesn't expose live sessions. `Auth.refresh` validates and **rotates** the token (the presented one is single-use), returning a fresh `%{access_token, refresh_token}`; expired/unknown/already-rotated tokens return `:invalid_token`. `Auth.logout` deletes the token (idempotent). Adds the `auth_token` schema convention (`schema "auth_tokens"`) and `auth.token_schema` / `auth.refresh_token_ttl` (default 30d) config. See [docs/modules.md](docs/modules.md#auth). (#164)
- **`Auth` module — email/password login** (`Auth.register/2`, `Auth.login/2`, `Auth.current_user/1`). A thin service layer over `Crypto` (password hashing), `JWT` (access tokens), and `Repo` (persistence) so a register/login/me flow is a few lines instead of hand-wiring all three. `register` hashes via `Crypto.hash_password` and inserts a user (returned without the password hash); `login` verifies the password and returns `%{user, access_token}` with a signed short-lived JWT; `current_user` resolves the user from the verified claims the `[:auth]` middleware attaches. Wrong password and unknown email both return `:invalid_credentials` in similar time (no user enumeration). Conventions are configurable via `Config` (`auth.secret`, `auth.user_schema`, `auth.access_token_ttl`). `Auth` maps to `winn_auth` in `winn_codegen_resolve`. See [docs/modules.md](docs/modules.md#auth). (#163)
- **`Crypto.hash_password/1` and `Crypto.verify_password/2`** — secure password hashing for login flows. Uses PBKDF2-HMAC-SHA256 (600,000 iterations, OWASP-recommended) with a per-call random 16-byte salt, via `crypto:pbkdf2_hmac/5` — no new dependencies. `hash_password` returns a self-describing PHC-style string (`$pbkdf2-sha256$i=<iter>$<salt_b64>$<hash_b64>`) so the cost can be raised — and bcrypt/argon2 added — later without invalidating existing hashes. `verify_password` recomputes with the embedded salt/iterations and compares constant-time, returning `false` (never crashing) on a malformed or non-string hash. Replaces the unsafe `Crypto.hash(:sha256, ...)`-on-a-password pattern. (#162)
- **`Timer.sleep(ms)`** — block the calling process for `ms` milliseconds. Useful in top-level scripts that need to keep the VM alive after kicking off supervisor-backed work (e.g. `pipeline` demos).
- **`Metrics.prometheus()`** — render the current metrics state as a Prometheus v0.0.4 text exposition binary. Counters, gauges, histograms (as summaries with `quantile="0.5|0.95|0.99"` labels), per-endpoint HTTP stats (`http_requests_total`, `http_errors_total`, `http_request_duration_ms`), and BEAM gauges (`beam_process_count`, `beam_memory_*_bytes`, `beam_uptime_ms`) all emit valid exposition format with `# TYPE` preambles. Float values use 3-decimal compact form. Lets a `/metrics` endpoint be one line of Winn (`Server.text(conn, Metrics.prometheus())`) — replaces the ~50-line Erlang exporter previously documented in the deployment guide. (#156)
- **Runtime bounds checking and safe defaults** — stdlib calls that used to raise on edge cases now return sentinel values instead, so production code paths can match on `nil` / `{error, …}` rather than wrapping every call in a try/rescue. (#58)
  - `List.first([])` / `List.last([])` → `nil` (was `:not_found`, see Breaking Changes)
  - `Map.get(key, map)` → `nil` for missing keys; `{error, :not_a_map}` when the second argument isn't a map
  - `String.slice(str, start, len)` → `""` for out-of-range start, negative start, negative length, or non-binary input (previously crashed with badarg)
  - Map field access `user.name` → `nil` when the key is missing (previously raised `{badkey, …}`); compiles to `maps:get(field, map, nil)`

### Developer Tooling
- **LSP Phase 1 — lint diagnostics** — `winn lsp` now publishes lint warnings alongside compile errors. Each warning carries its rule name (e.g. `function_name_convention`) in the `code` field so editors can group and filter rules. Closing a document clears its diagnostics and removes it from the in-memory buffer. (#118)
- **LSP Phase 2 — navigation** — `winn lsp` now supports outline panels, hover info, and go-to-definition. (#119)
  - **`textDocument/documentSymbol`** — module/agent containers with function/import/alias children, mapped to LSP `SymbolKind`s.
  - **`textDocument/hover`** — markdown signature (`**name/arity** — \`def name(params)\``) plus any consecutive `#` doc comments immediately preceding the def.
  - **`textDocument/definition`** — local function calls jump to their def in the current file. `Module.fun()` calls resolve to `<lowercase_mod>.winn` under `src/`, `src/models/`, `src/controllers/`, or `src/tasks/`. Stdlib calls (IO, String, Enum, …) return null.

### Linter
- **`unused_private_function`** rule — warns when a `private def` has no call sites in the same module.

### Tooling
- **`winn docs`** — generated API docs now skip private functions.

### Documentation
- **Production deployment guide** — new `docs/deployment.md` covering BEAM scheduler sizing against Kubernetes CPU limits, `ERL_FLAGS` recipes, structured JSON logging with `Logger` plus Promtail/Loki + Datadog wiring, a drop-in Prometheus `/metrics` handler built on `Metrics.snapshot()`/`http_snapshot()`/`beam_stats()`, SIGTERM drain via OTP with the readiness-flip `preStop` pattern, a complete Kubernetes Deployment + Service + Ingress template (incl. 1Password Operator), a multi-stage Dockerfile with a non-root runtime image, and a merge-ready pre-flight checklist. Linked from `docs/getting-started.md`. (#153)

## [0.9.0] - 2026-04-09

### Breaking Changes
- **`winn c` shortcut changed** — `c` now maps to `compile` (was `create`). Use `g` for generate/create instead.
- **Generator paths reorganized** — `winn create` now outputs to Rails-style subdirectories. Existing projects must move files manually:
  - Models: `src/*.winn` → `src/models/*.winn`
  - Migrations: `migrations/` → `db/migrations/`
  - Tasks: `tasks/` → `src/tasks/`
  - Routers renamed to Controllers: `src/name.winn` → `src/controllers/name_controller.winn` (module `NameController`)

### Developer Tooling
- **`winn fmt`** — code formatter for consistent style (`winn fmt`, `winn fmt --check`)
- **`winn lint`** — static analysis linter with 10 rules: unused variables, unused imports/aliases, naming conventions, redundant boolean comparisons, empty function bodies, pipe-into-literal, single pipe, and large function detection
- **`winn lsp`** — Language Server Protocol implementation with stdio transport, inline compile error diagnostics, and dot-triggered autocomplete for 14 modules
- **`winn new` improved** — three scaffold modes: default (full structure with test/, config/, README, .env.example), `--api` (router + health endpoint), `--minimal` (just src/ and rebar.config)
- **Command shortcuts** — single-letter shortcuts: `r` (run), `s` (start), `t` (test), `f` (fmt), `l` (lint), `d` (docs), `w` (watch), `g` (create/generate), `c` (compile), `con` (console)
- **Grouped help menu** — `winn help` now organizes commands into categories

### Compiler
- **Codegen split** — `winn_codegen.erl` split into `winn_codegen_resolve.erl` (module name resolution) and `winn_codegen_pattern.erl` (pattern generation) for maintainability

---

## [0.8.1] - 2026-04-03

### Fixes
- **Agent tests passing** — removed stale committed `winn_parser.erl` generated file that was shadowing the yecc-compiled parser and preventing `agent` keyword from being recognized
- **CI cache correctness** — updated cache key to include `.yrl`/`.xrl` grammar file hashes, preventing stale parser beams from being restored across builds

## [0.8.0] - 2026-04-02

### Language
- **`agent` keyword** — first-class stateful actors as a language primitive, compiles to GenServer with zero boilerplate
- **`@state` syntax** — `@count` reads and `@count = expr` writes agent state, desugared in the transform phase
- **`async def`** — fire-and-forget agent functions via `gen_server:cast`
- **Agent start with overrides** — `Counter.start()` uses defaults, `Counter.start(%{count: 100})` merges overrides

### Web Framework
- **Static file serving** — `{:static, "/public", "static/"}` route option for CSS/JS/images
- **CORS middleware** — built-in CORS with configurable origins, methods, headers, preflight handling
- **Auth middleware** — Bearer token extraction and JWT verification with path exclusions
- **Health checks** — `Health.liveness`, `Health.readiness`, `Health.detailed` for Kubernetes probes

## [0.7.0] - 2026-04-01

### Core Stdlib
- **File I/O** — `File.read`, `File.write`, `File.exists?`, `File.delete`, `File.list`, `File.read_lines`, `File.append`, `File.mkdir`
- **Regex** — `Regex.match?`, `Regex.replace`, `Regex.scan`, `Regex.split`, `Regex.named_captures`
- **Timer** — `Timer.every`, `Timer.after`, `Timer.cancel` for periodic tasks
- **Retry** — `Retry.run` with exponential backoff and jitter
- **System.get_env default** — `System.get_env("KEY", "fallback")` with 2-arity
- **DateTime** — `DateTime.add`, `DateTime.before?`, `DateTime.after?`
- **String** — `String.pad_left`, `String.pad_right`, `String.repeat`, `String.byte_size`, safe `String.slice`

### Package System
- **`winn add <package>`** — install packages from GitHub repos
- **`winn remove <package>`** — uninstall packages
- **`winn packages`** — list installed packages
- **`winn install`** — install all from `package.json`
- **`package.json`** — project manifest for declaring package dependencies
- Packages are written in Winn (no Erlang required) with a `package.json` manifest
- `winn new` scaffold now generates `package.json`

## [0.6.0] - 2026-04-01

### Observability
- **Metrics module** — `Metrics.increment`, `Metrics.set`, `Metrics.observe`, `Metrics.time` for counters, gauges, histograms
- **HTTP metrics** — `Metrics.record_http` tracks per-endpoint request count, latency percentiles, error rates
- **BEAM VM stats** — `Metrics.beam_stats()` returns process count, memory, schedulers, uptime
- **Snapshots** — `Metrics.snapshot()` and `Metrics.http_snapshot()` for reading all metrics
- **`winn metrics`** — live terminal dashboard showing HTTP stats, BEAM health, custom metrics
- **`winn bench`** — built-in load testing with concurrent workers, P50/P95/P99 latency stats

## [0.5.0] - 2026-04-01

### Database
- **Connection pooling** — `Repo.configure(%{pool_size: 10})` starts a GenServer-based connection pool; connections are checked out/in automatically
- **Transactions** — `Repo.transaction(fn() => ... end)` wraps operations in BEGIN/COMMIT/ROLLBACK
- **Rails-style model methods** — schema modules auto-generate `all()`, `find(id)`, `find_by(field, value)`, `create(attrs)`, `delete(record)`, `count()`
- **Extended query builder** — `query.order_by`, `query.select`, `query.count`, `Repo.aggregate` (sum/avg/min/max)
- **SQLite support** — `Repo.configure(%{adapter: :sqlite, database: "app.db"})` with automatic SQL dialect translation

### Tooling
- **`winn migrate`** — run pending database migrations with `schema_migrations` tracking
- **`winn rollback`** — rollback migrations with `--step N` support
- **`winn migrate --status`** — show applied vs pending migrations
- **`winn release`** — build production releases, `--docker` generates a Dockerfile
- **`winn create` / `winn c`** — code generators for model, migration, task, router, scaffold
- **`winn task <name>`** — run project tasks from the CLI with Rails-style colon syntax (e.g., `winn task db:seed`)

## [0.4.0] - 2026-03-29

### Language Features
- **Pipe assign (`|>=`)** — capture pipe chain results into a variable
- **Triple-quoted strings (`"""..."""`)** — multi-line strings with auto-dedent and embedded quotes
- **Default parameter values** — `def greet(name, greeting = "Hello")` with multiple arities generated
- **Struct types** — `struct [:name, :email]` generates `new/0`, `new/1`, `__struct__/0`, `__fields__/0`
- **Protocols** — `protocol do ... end` defines interfaces, `impl ProtocolName do ... end` implements them for struct types with runtime ETS dispatch
- **Significant newlines** — multi-expression switch/rescue clause bodies without `do...end` wrappers (backward compatible)
- **Block comments** — `#| ... |#` for multi-line comments, can comment out blocks of code

## [0.3.0] - 2026-03-28

### Language Features
- **`import Module`** — bring a module's functions into scope as local calls
- **`alias Parent.Child`** — use a short name for a dotted module path
- Dotted module names (`module MyApp.Router`), `?` in function names, module names as expressions

### Testing Framework
- **`winn test`** — run Winn tests from the CLI
- **`use Winn.Test`**, **`assert(expr)`**, **`assert_equal(expected, actual)`**
- Test discovery, colorized output, exit codes

### Tooling
- **`winn docs`** — generate Markdown API docs with Mermaid dependency graph
- **`winn watch`** — file watcher with hot code reloading and live terminal dashboard
- **`winn watch --start`** — watch mode + starts the app
- **`Repo.configure`** — Winn-native database configuration
- **`Repo.execute`** — raw SQL queries

### Compiler
- **`module_info/0` and `module_info/1`** — now generated for all compiled modules

## [0.2.0] - 2026-03-28

### Language Features
- **String interpolation** — `"Hello, #{name}!"`
- **Standalone lambdas** — `fn(x) => x * 2 end`
- **For comprehensions** — `for x in list do x * 2 end`
- **Range literals** — `1..10` produces `[1, 2, 3, ..., 10]`
- **Map field access** — `user.name` instead of `Map.get(:name, user)`
- **Pattern assignment** — `{:ok, val} = expr`
- **Multi-line switch/rescue bodies** — `=> do ... end`
- **Type builtins** — `to_string()`, `to_integer()`, `to_float()`, `to_atom()`, `inspect()` callable directly

### Modules
- **HTTP server** — Cowboy-powered with route matching, JSON responses, path/query params
- **Middleware** — `middleware/0` callback on routers for auth, CORS, logging
- **JSON** — `JSON.encode()` / `JSON.decode()`
- **Server helpers** — `Server.set_header()`, `Server.method()`, `Server.path()`

### CLI
- **`winn start`** — compile all files, load deps, start app, keep VM alive
- **`winn console`** — interactive REPL with variable persistence
- **`winn version`** / `winn -v` — show version
- **`winn compile`** — now searches `src/` first, shows file count
- **`winn run`** — reads module name from source (not filename)
- **`winn new`** — converts project names to PascalCase module names

### Compiler
- **Error messages** — Elm/Rust-style output with source context, caret pointers, hints, ANSI colors
- Transform/codegen errors caught and formatted (no more raw Erlang stack traces)

### Tooling
- **Homebrew** — `brew tap gregwinn/winn && brew install winn`
- **VS Code extension** — syntax highlighting + compile-on-save diagnostics
- **`/release` Claude skill** — automated versioning, tagging, GitHub release, Homebrew update

### Infrastructure
- 313 tests, 0 failures
- Merged develop into main
- GitHub Actions CI

## [0.1.1] - 2026-03-27

### Fixes
- `winn new hello_world` now generates `module HelloWorld` (PascalCase) instead of `module hello_world`

## [0.1.0] - 2026-03-27

### Language Features
- Modules, functions, pattern matching, pipes, closures
- `if/else`, `switch`, guards (`when`), `try/rescue`
- `match...end` blocks with `ok`/`err` sugar
- `do |x| ... end` block syntax for iterators

### Standard Library
- IO (puts, print, inspect)
- String (upcase, downcase, trim, split, replace, etc.)
- Enum (map, filter, reduce, each, find, sort, join, etc.)
- List (first, last, length, reverse, flatten, append, contains?)
- Map (merge, get, put, keys, values, has_key?, delete)
- System (get_env, put_env)
- UUID (v4)
- DateTime (now, to_iso8601, from_iso8601, diff, format)
- Logger (info, warn, error, debug — JSON structured output)
- Crypto (hash, hmac, random_bytes, base64_encode, base64_decode)

### Modules
- HTTP client (hackney + jsone) — GET, POST, PUT, PATCH, DELETE with auto JSON
- Config (ETS-backed) — get, put, load
- Task/Async — spawn, async, await, async_all
- JWT (pure Erlang HS256) — sign, verify with expiry
- WebSockets (gun) — connect, send, recv, close

### OTP
- `use Winn.GenServer` — auto start_link, behaviour attribute
- `use Winn.Supervisor` — auto start_link, behaviour attribute
- `use Winn.Application` — behaviour attribute
- `use Winn.Schema` — schema DSL with field definitions

### ORM
- Schema DSL with `schema "table" do field :name, :type end`
- Changeset validation (required, length)
- Repo (insert, get, all, update, delete) via epgsql

### CLI
- `winn new <name>` — scaffold a project
- `winn compile [file]` — compile to .beam
- `winn run <file>` — compile and run
- `winn help` — usage info

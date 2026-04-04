# Changelog

All notable changes to the Winn language are documented here.

## [Unreleased]

### Breaking Changes
- **Generator paths reorganized** — `winn create` now outputs to Rails-style subdirectories. Existing projects must move files manually:
  - Models: `src/*.winn` → `src/models/*.winn`
  - Migrations: `migrations/` → `db/migrations/`
  - Tasks: `tasks/` → `src/tasks/`
  - Routers renamed to Controllers: `src/name.winn` → `src/controllers/name_controller.winn` (module `NameController`)

### CLI
- **`winn new`** — scaffold now creates `src/models/`, `src/controllers/`, `src/tasks/`, `test/`, `db/migrations/`, `config/`, and `db/seeds.winn`
- **`winn create model`** — output path: `src/models/<name>.winn`
- **`winn create migration`** — output path: `db/migrations/<timestamp>_<name>.winn`
- **`winn create task`** — output path: `src/tasks/<name>.winn`
- **`winn create router`** — output path: `src/controllers/<name>_controller.winn`, module `<Name>Controller`
- **`winn create scaffold`** — model → `src/models/`, controller → `src/controllers/`, test → `test/`
- **`winn migrate`** — reads migrations from `db/migrations/` (was `migrations/`)

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

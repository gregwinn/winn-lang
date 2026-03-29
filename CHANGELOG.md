# Changelog

All notable changes to the Winn language are documented here.

## [Unreleased]

### Language Features
- **Pipe assign (`|>=`)** — capture pipe chain results into a variable
- **Triple-quoted strings (`"""..."""`)** — multi-line strings with auto-dedent and embedded quotes

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

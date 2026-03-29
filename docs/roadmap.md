# Winn Roadmap

## Current Status — v0.3.2

360 tests passing. Homebrew install (`brew install gregwinn/winn/winn`). VS Code extension with syntax highlighting and compile-on-save diagnostics.

### Completed

| Area | Feature | Version |
|------|---------|---------|
| Language | if/else, switch, guards (when), try/rescue | v0.1.0 |
| Language | String interpolation (`"#{expr}"`), standalone lambdas (`fn => end`) | v0.2.0 |
| Language | For comprehensions, range literals (`1..10`), pattern assignment | v0.2.0 |
| Language | Map field access (`user.name`), multi-line switch/rescue bodies | v0.2.0 |
| Language | `import Module`, `alias Parent.Child` | v0.3.0 |
| Language | Dotted module names (`module MyApp.Router`), `?` in names | v0.3.2 |
| Language | Module names as expressions (`Repo.insert(Post, data)`) | v0.3.1 |
| Runtime | System (env vars), UUID, DateTime, Logger, Crypto | v0.1.0 |
| Runtime | JSON module, type builtins (to_string, to_integer, etc.) | v0.2.0 |
| Modules | HTTP client (hackney), HTTP server (Cowboy), middleware | v0.2.0 |
| Modules | Config (ETS), Task/Async, JWT (pure Erlang), WebSockets (gun) | v0.1.0 |
| OTP | GenServer, Supervisor, Application, Task behaviours | v0.1.0 |
| ORM | Schema DSL, Changeset, Repo (PostgreSQL via epgsql) | v0.1.0 |
| Testing | `winn test`, `use Winn.Test`, `assert`/`assert_equal` | v0.3.0 |
| Tooling | CLI (new/compile/run/start/test/docs/watch/version), Homebrew | v0.3.0 |
| Tooling | VS Code extension, compiler error messages with source context | v0.2.0 |
| Tooling | `winn docs` with Mermaid dependency graph | v0.3.0 |
| Tooling | `winn watch` with live terminal dashboard | v0.3.0 |
| Tooling | CI (GitHub Actions), CHANGELOG, merge to main | v0.2.0 |
| Tooling | REPL (`winn console`), dependency management (`winn deps`) | v0.2.0 |
| Compiler | `module_info/0,1` generated for all compiled modules | v0.3.0 |

---

## Next Up — Planned Features

### N1 — Merge to Main and Stabilize

**Priority:** High
**Effort:** Small

The `develop` branch is significantly ahead of `main`. Merge, tag properly, and establish a release cadence.

- Merge `develop` into `main`
- Set up CI (GitHub Actions) running `rebar3 eunit` on push
- Add a `CHANGELOG.md`

---

### N2 — REPL (`winn shell`)

**Priority:** High
**Effort:** Medium

An interactive Winn session for learning, prototyping, and debugging.

**Syntax:**
```
$ winn shell
Winn 0.2.0 (Erlang/OTP 28)

winn> 1 + 2
3

winn> name = "Alice"
"Alice"

winn> "Hello, #{name}!"
"Hello, Alice!"

winn> Enum.map(1..5) do |x| x * x end
[1, 4, 9, 16, 25]
```

**Implementation:**
- Add `winn shell` command to `winn_cli.erl`
- Read-eval-print loop: read line → lex → parse → transform → codegen → compile → eval → print
- Wrap each input in a temporary module, compile in-memory, call, print result
- Keep variable state across evaluations (accumulate bindings)
- Support multi-line input (detect incomplete expressions by trailing operators/unclosed blocks)
- History via Erlang's built-in `io:get_line` or link to `edlin`

---

### N3 — Package/Dependency Management (`winn deps`)

**Priority:** High
**Effort:** Medium

Install and manage Erlang/Hex dependencies from Winn projects.

**Syntax:**
```sh
# Add a dependency
winn deps add cowboy 2.12.0

# Install all dependencies
winn deps install

# List dependencies
winn deps list

# Remove a dependency
winn deps remove cowboy
```

**Implementation:**
- Read/write `rebar.config` deps section programmatically
- `winn deps install` → runs `rebar3 get-deps && rebar3 compile`
- `winn deps add <name> <version>` → edits rebar.config, then installs
- Consider a `winn.toml` or `winn.lock` file for Winn-native config (maps to rebar.config)
- Future: Winn package registry (like Hex.pm)

---

### N4 — Testing Framework (`winn test`)

**Priority:** High
**Effort:** Medium

Write and run tests in Winn, not just Erlang.

**Syntax:**
```winn
module UserTest
  use Winn.Test

  def test_create_user()
    user = User.new(%{name: "Alice"})
    assert(user.name == "Alice")
  end

  def test_validate_required()
    changeset = Changeset.new(User.new(%{}), %{})
    changeset = Changeset.validate_required(changeset, [:name])
    assert(Changeset.valid(changeset) == false)
  end
end
```

```sh
winn test                    # Run all tests in test/
winn test test/user_test.winn  # Run a specific test file
```

**Implementation:**
- `use Winn.Test` adds test runner behaviour
- `assert/1` and `assert_equal/2` as runtime functions in `winn_test.erl`
- `winn test` compiles all `test/*.winn` files, discovers test modules (functions starting with `test_`), runs them, reports results
- Colorized pass/fail output with timing
- Exit code 0 on all pass, 1 on any failure

---

### N5 — Import and Alias

**Priority:** Medium
**Effort:** Small

The lexer already has `import` and `alias` tokens, but they're not implemented in the parser/transform.

**Syntax:**
```winn
module MyApp
  import Enum          # brings Enum functions into scope as local calls
  alias MyApp.Auth     # Auth.verify() instead of MyApp.Auth.verify()

  def process(list)
    map(list) do |x| x * 2 end    # instead of Enum.map(...)
  end
end
```

**Implementation:**
- Parser: `import_stmt -> 'import' module_name` and `alias_stmt -> 'alias' module_name`
- Transform: `import` rewrites local calls to dot calls on the imported module; `alias` maps short names to full module paths
- No codegen changes needed — it's purely a transform-level rewrite

---

### N6 — CLI Task Runner (`winn task`)

**Priority:** Medium
**Effort:** Medium

Run project tasks from the CLI. Already partially scaffolded (`use Winn.Task` exists).

**Syntax:**
```sh
winn task db.migrate
winn task db.seed
winn task routes
```

```winn
module Tasks.Db.Migrate
  use Winn.Task

  def run(args)
    IO.puts("Running migrations...")
    # Execute SQL migration files
  end
end
```

**Implementation:**
- Add `winn task <name>` to `winn_cli.erl`
- Compile all `src/` and `tasks/` directories
- Discover task modules by scanning beams for `-behaviour(winn_task)`
- Map dotted names: `db.migrate` → module `tasks.db.migrate`
- Built-in tasks: `db.migrate`, `db.rollback`, `db.seed` (call `winn_repo` helpers)

---

### N7 — Documentation Generator (`winn docs`)

**Priority:** Medium
**Effort:** Medium

Generate HTML or Markdown documentation from source code comments.

**Syntax:**
```winn
# Public: Greet a user by name.
#
# name - The name to greet (string).
#
# Returns a greeting string.
def greet(name)
  "Hello, #{name}!"
end
```

```sh
winn docs                # Generate docs to docs/ from src/
winn docs --format html  # HTML output
```

**Implementation:**
- Parse `#` comments preceding `def` and `module` declarations
- Extract function signatures, module names, and doc comments
- Generate Markdown (default) or HTML output
- Include a table of contents and module index
- Could use TomDoc or a simple custom format

---

### N8 — Hot Code Reloading (`winn watch`)

**Priority:** Medium
**Effort:** Medium

Automatically recompile and reload modules when source files change.

**Syntax:**
```sh
winn watch              # Watch src/, recompile on change
winn watch --start      # Watch + start the app (like winn start but auto-reloads)
```

**Implementation:**
- Use Erlang's `filelib` or a file system watcher (inotify on Linux, fsevents on macOS)
- On file change: recompile the changed `.winn` file, hot-reload the beam via `code:load_file/1`
- For server apps: reload without dropping connections (BEAM's hot code swap)
- Debounce rapid changes (300ms)

---

### N9 — Database Migrations

**Priority:** Medium
**Effort:** Medium

Versioned database schema migrations.

**File structure:**
```
migrations/
├── 001_create_users.winn
├── 002_add_email_to_users.winn
└── 003_create_posts.winn
```

**Syntax:**
```winn
module Migrations.CreateUsers
  def up()
    Repo.execute("CREATE TABLE users (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      email VARCHAR(255),
      created_at TIMESTAMP DEFAULT NOW()
    )")
  end

  def down()
    Repo.execute("DROP TABLE users")
  end
end
```

```sh
winn task db.migrate           # Run pending migrations
winn task db.rollback          # Rollback last migration
winn task db.status            # Show migration status
```

**Implementation:**
- `winn_repo.erl` gets `execute/1` for raw SQL
- Migration runner tracks applied migrations in a `schema_migrations` table
- Migrations run in a transaction
- Integrates with N6 (task runner)

---

### N10 — Significant Newlines (Breaking Change)

**Priority:** Low
**Effort:** Large

Remove the need for `do...end` wrappers in switch/rescue clause bodies by making newlines significant.

**Before (current):**
```winn
switch status
  :active => do
    Logger.info("active")
    :ok
  end
  _ => :other
end
```

**After:**
```winn
switch status
  :active =>
    Logger.info("active")
    :ok
  _ => :other
end
```

**Implementation:**
- Lexer emits newline tokens when not inside `()`, `[]`, `{}`
- Parser uses newlines as expression separators and clause body terminators
- Requires depth tracking in the lexer (bracket nesting counter)
- Large change — touches most parser rules
- Consider as a v1.0 breaking change

---

### N11 — Pipe Assign (`|>=`)

**Priority:** Low
**Effort:** Small

Pipe result into a variable assignment, reducing intermediate bindings.

**Syntax:**
```winn
data
  |> JSON.decode()
  |> Map.get(:users)
  |>= users            # assigns to users variable

IO.puts("Got #{to_string(List.length(users))} users")
```

**Implementation:**
- Lexer: add `|>=` token
- Parser: `pipe_assign -> pipe_expr '|>=' ident` producing `{assign, Line, Var, PipeResult}`
- No transform/codegen changes — just syntactic sugar

---

### N12 — Struct Types

**Priority:** Low
**Effort:** Medium

Named structs with compile-time field validation, beyond plain maps.

**Syntax:**
```winn
module User
  defstruct [:name, :email, :age]
end

user = User.new(%{name: "Alice", age: 30})
user.name   # => "Alice"
user.role   # => compile error: User has no field :role
```

**Implementation:**
- `defstruct` keyword in lexer/parser
- Transform generates `new/1` function that validates keys
- Structs are maps with a `__struct__: ModuleName` key (like Elixir)
- Optional: compile-time field checking in semantic analysis

---

### N13 — Protocols / Behaviours

**Priority:** Low
**Effort:** Large

Define interfaces that multiple modules can implement.

**Syntax:**
```winn
module Printable
  defprotocol do
    def to_s(value)
  end
end

module User
  defimpl Printable do
    def to_s(user)
      "User(#{user.name})"
    end
  end
end
```

**Implementation:**
- Protocol dispatch table (ETS or compiled module)
- `defprotocol` defines the interface, `defimpl` provides implementations
- Dispatch based on the `__struct__` key or atom type
- Depends on N12 (Structs) for clean dispatch

---

### N14 — Deployment (`winn release`)

**Priority:** Low
**Effort:** Medium

Build self-contained releases for production deployment.

**Syntax:**
```sh
winn release              # Build a release tarball
winn release --docker     # Generate a Dockerfile
```

**Implementation:**
- Wraps `rebar3 as prod release` or `rebar3 as prod tar`
- Generates a `rel/` config from project structure
- Optional Dockerfile generation with Erlang base image
- Includes all compiled beams + runtime deps

---

## Ecosystem & Community

### E1 — Project Website

- Landing page explaining Winn
- Interactive playground (compile Winn in the browser via WASM or server-side)
- Documentation hosted on GitHub Pages

### E2 — Example Projects

- **winn-todo-api** — REST API with Postgres, JWT auth, full CRUD
- **winn-chat** — WebSocket chat server
- **winn-github-sync** — Worker that polls GitHub API and saves to DB

### E3 — Package Registry

- Winn-native package registry (like Hex.pm)
- `winn publish` to push packages
- Dependency resolution beyond raw rebar.config

---

## Suggested Build Orders

**Make it real (build a production service):**
N1 (stabilize) → N4 (tests) → N9 (migrations) → N6 (tasks) → E2 (example projects)

**Make it developer-friendly:**
N2 (REPL) → N5 (import/alias) → N8 (hot reload) → N7 (docs)

**Make it production-ready:**
N1 (stabilize) → N3 (deps) → N14 (releases) → N9 (migrations)

**Make it a real language:**
N10 (newlines) → N12 (structs) → N13 (protocols) → N5 (import/alias)

---

## Status

| Item | Description | Status |
|------|-------------|--------|
| L1-L4 | if/else, switch, guards, try/rescue | done |
| R1-R5 | env vars, UUID, DateTime, logging, crypto | done |
| M1-M6 | HTTP client, config, application, tasks, JWT, WebSockets | done |
| HI1-HI6 | interpolation, field access, lambdas, pattern assign, JSON, for | done |
| S1 | HTTP server (Cowboy) + middleware | done |
| MI1-MI5 | middleware, type builtins, ranges, multi-line bodies, error messages | done |
| Tooling | CLI (new/compile/run/start/version), Homebrew, VS Code extension | done |
| N1 | Merge to main, CI, changelog | **done** (v0.2.0) |
| N2 | REPL (winn console) | **done** (v0.2.0) |
| N3 | Package management (winn deps) | **done** (v0.2.0) |
| N4 | Testing framework (winn test) | **done** (v0.3.0) |
| N5 | Import and alias | **done** (v0.3.0) |
| N6 | CLI task runner (winn task) | planned |
| N7 | Documentation generator (winn docs) | **done** (v0.3.0) |
| N8 | Hot code reloading (winn watch) | **done** (v0.3.0) |
| N9 | Database migrations | planned |
| N10 | Significant newlines | planned |
| N11 | Pipe assign (\|>=) | planned |
| N12 | Struct types | planned |
| N13 | Protocols / behaviours | planned |
| N14 | Deployment (winn release) | planned |
| E1 | Project website | planned |
| E2 | Example projects | planned |
| E3 | Package registry | planned |

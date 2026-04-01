# Winn CLI

The `winn` command-line tool creates, compiles, and runs Winn programs.

## Installation

### Homebrew (recommended)

```sh
brew tap gregwinn/winn
brew install winn
```

### From Source

```sh
git clone https://github.com/gregwinn/winn-lang.git
cd winn-lang
rebar3 escriptize
cp _build/default/bin/winn /usr/local/bin/
```

---

## Commands

### `winn new <name>`

Create a new Winn project with the standard directory structure.

```sh
winn new my_app
```

Creates:

```
my_app/
├── rebar.config       # Erlang build configuration
├── .gitignore         # Ignores _build/, ebin/, *.beam
└── src/
    └── my_app.winn    # Starter module with main()
```

The generated `src/my_app.winn` (note: project names are auto-converted to PascalCase module names):

```winn
module MyApp
  def main()
    IO.puts("Hello from my_app!")
  end
end
```

---

### `winn compile [file]`

Compile `.winn` files to `.beam` bytecode.

```sh
# Compile a single file — output to ebin/
winn compile src/my_app.winn

# Compile all .winn files in src/ (falls back to current dir)
winn compile
# => Compiled 3 file(s) to ebin/
```

Output `.beam` files are written to `ebin/`. The directory is created automatically.

**Compilation pipeline:**

1. Lexer tokenizes the source (`.winn` → tokens)
2. Parser builds the AST (tokens → syntax tree)
3. Semantic analysis checks scope and variables
4. Transform desugars pipes, match blocks, closures, interpolation, schemas
5. Codegen produces Core Erlang via the `cerl` module
6. Core Erlang is compiled to `.beam` bytecode

**Error output:**

If compilation fails, you get a clear error message pointing to the issue:

```
-- Syntax Error ----------------------------- src/app.winn --

3 |     x +
4 |   end
  |   ^^^
5 | end
  Unexpected 'end'.
  Hint: Did you close a block too early, or forget an expression?
```

Errors are printed to stderr. Exit code is 1 on failure, 0 on success.

---

### `winn run <file>`

Compile a single `.winn` file and immediately run it.

```sh
winn run src/hello.winn
```

How it works:

1. Compiles the file to a temporary directory
2. Reads the module name from the source (`module HelloWorld` → `helloworld`)
3. Loads the `.beam` into the Erlang VM
4. Calls `Module:main()` (falls back to `main/1` with `[]`)
5. Cleans up the temp directory

Best for quick scripts and single-file programs.

---

### `winn start [module]`

Compile a full project and start it with the VM kept alive.

```sh
# Auto-detect main module from first .winn file
winn start

# Specify a module explicitly
winn start my_app
```

How it works:

1. Compiles all `.winn` files in `src/` (or current directory)
2. Adds `ebin/` and `_build/` dependency paths to the code path
3. Starts OTP applications (crypto, ssl, cowboy, hackney, gun)
4. Calls `Module:main()` on the detected or specified module
5. **Keeps the VM running** after `main()` returns

Use `winn start` for:
- HTTP servers (the VM must stay alive to serve requests)
- GenServer / Supervisor applications
- Any long-running service

---

### `winn test [file]`

Run Winn tests.

```sh
# Run all tests in test/
winn test

# Run a specific test file
winn test test/math_test.winn
```

Write tests using `use Winn.Test`:

```winn
module MathTest
  use Winn.Test

  def test_addition()
    assert(1 + 1 == 2)
  end

  def test_string_equality()
    result = "hello" <> " world"
    assert_equal("hello world", result)
  end
end
```

**Assertions:**

| Function | Description |
|----------|-------------|
| `assert(expr)` | Passes if `expr` is `true` |
| `assert_equal(expected, actual)` | Passes if `expected =:= actual` |

**How it works:**

1. Compiles all `test/*.winn` files (and `src/*.winn` for project modules)
2. Loads compiled beams into the VM
3. Discovers functions named `test_*` in test modules
4. Runs each test function, catches assertion failures
5. Prints colorized pass/fail results with timing

Exit code is 0 when all tests pass, 1 on any failure.

---

### `winn docs [file]`

Generate API documentation with a module dependency graph.

```sh
# Generate docs for all src/*.winn files
winn docs

# Generate docs for a specific file
winn docs src/api.winn
```

Output is written to `doc/api/`:

```
doc/api/
├── index.md         # Module list + Mermaid dependency graph
├── api.md           # Per-module API docs
├── auth.md
└── user.md
```

**Features:**

- Extracts `#` doc comments before `def` and `module` declarations
- Generates per-module Markdown files with function signatures
- Builds a **Mermaid dependency graph** showing which modules call which (renders on GitHub)
- Handles multi-clause functions
- Skips stdlib modules (IO, Enum, String, etc.) in the graph

---

### `winn watch`

Watch source files and hot-reload modules on change with a live terminal dashboard.

```sh
# Watch and recompile only
winn watch

# Watch + start the app (like winn start but with auto-reload)
winn watch --start
```

The dashboard shows:

```
┌─ Winn Watch ─────────────────────────────────┐
│ Watching src/ (3 modules)                     │
│                                               │
│  ✓ Api          reloaded 2s ago               │
│  ✓ Auth         reloaded 14s ago              │
│  ✗ User         compile error                 │
│    └ line 12: undefined var `nam`             │
│                                               │
│ Reloads: 7  Errors: 1  Uptime: 2m 30s        │
└───────────────────────────────────────────────┘
```

**Features:**
- Polls `src/*.winn` every 500ms for changes
- Hot-reloads changed modules via BEAM code swap (no restart needed)
- Compile errors keep the last working version loaded
- Live dashboard with per-module status, reload times, and error details
- `--start` flag starts OTP apps and calls `main()` before watching

---

### `winn migrate`

Run database migrations.

```sh
winn migrate              # Run all pending migrations
winn migrate --step 2     # Run next 2 migrations
winn migrate --status     # Show migration status
winn rollback             # Rollback last migration
winn rollback --step 3    # Rollback last 3 migrations
```

Migrations live in `migrations/*.winn` with `up()` and `down()` functions:

```winn
module Migrations.CreateUsers
  def up()
    Repo.execute("CREATE TABLE users (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      email VARCHAR(255)
    )")
  end

  def down()
    Repo.execute("DROP TABLE users")
  end
end
```

Applied migrations are tracked in a `schema_migrations` table (auto-created). Files are sorted by name, so use numeric prefixes: `001_create_users.winn`, `002_add_email.winn`.

---

### `winn task <name> [args...]`

Run project tasks. Tasks are Winn modules with `use Winn.Task` and a `run/1` function.

```sh
winn task db:migrate
winn task db:seed --file data.csv
winn task routes
```

Task names use colons for namespacing (like Rails) — `db:migrate` maps to `module Tasks.Db.Migrate`:

```winn
module Tasks.Db.Migrate
  use Winn.Task

  def run(args)
    IO.puts("Running migrations...")
  end
end
```

Tasks are discovered from `tasks/*.winn` and `src/*.winn`. The task runner compiles all source files, finds the matching module, and calls `run/1` with any extra CLI arguments.

---

### `winn deps`

Manage project dependencies.

```sh
# List current dependencies
winn deps list

# Add a dependency (fetches and compiles automatically)
winn deps add cowboy 2.12.0

# Remove a dependency
winn deps remove cowboy

# Fetch and compile all dependencies
winn deps install
```

Dependencies are stored in `rebar.config` in standard Erlang format. Under the hood, `winn deps install` runs `rebar3 get-deps && rebar3 compile`.

---

### `winn version`

Print the version.

```sh
winn version
# => winn 0.7.0

# Also works with flags:
winn -v
winn --version
```

---

### `winn help`

Print usage information.

```sh
winn help
```

---

## Typical Workflows

### Quick script

```sh
winn run hello.winn
```

### Web service

```sh
winn new my_api
cd my_api
# Edit src/*.winn files
winn start
# Server is running, hit it with curl
```

### Multi-file project

```sh
winn compile              # Compile all src/*.winn to ebin/
winn start                # Start with deps loaded
```

---

## Programmatic API

Drive the Winn compiler from Erlang code or the rebar3 shell:

```erlang
%% Compile a file to a directory
winn:compile_file("src/hello.winn", "ebin").

%% Compile a string (useful for testing)
winn:compile_string(
  "module Test\n  def main()\n    IO.puts(\"hi\")\n  end\nend",
  "test.winn",
  "ebin"
).
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Compilation error, runtime error, or unknown command |

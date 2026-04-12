# Winn CLI

## Install

```sh
# macOS
brew tap gregwinn/winn && brew install winn

# Linux (curl)
curl -fsSL https://winn.ws/install.sh | bash

# Ubuntu / Debian
curl -fsSL https://winn.ws/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/winn.gpg
echo "deb [signed-by=/usr/share/keyrings/winn.gpg] https://gregwinn.github.io/apt.winn.ws stable main" \
  | sudo tee /etc/apt/sources.list.d/winn.list
sudo apt update && sudo apt install winn

# Fedora / RHEL
sudo dnf config-manager --add-repo https://gregwinn.github.io/rpm.winn.ws/winn.repo
sudo dnf install winn
```

## Quick Reference

| Command | Shortcut | Description |
|---------|----------|-------------|
| [`winn new <name>`](#winn-new) | | Create a new project |
| [`winn run <file>`](#winn-run) | `r` | Compile and run a file |
| [`winn start [module]`](#winn-start) | `s` | Start project (keeps VM alive) |
| [`winn test [file]`](#winn-test) | `t` | Run tests |
| [`winn watch [--start]`](#winn-watch) | `w` | Watch + hot-reload |
| [`winn console`](#winn-console) | `con` | Interactive REPL |
| [`winn compile [file]`](#winn-compile) | `c` | Compile `.winn` files |
| [`winn fmt [file]`](#winn-fmt) | `f` | Format code (`--check` for CI) |
| [`winn lint [file]`](#winn-lint) | `l` | Static analysis linter |
| [`winn docs [file]`](#winn-docs) | `d` | Generate API docs |
| [`winn lsp`](#winn-lsp) | | Start language server (stdio) |
| [`winn create <type>`](#winn-create) | `g` | Generate code (model, migration, ...) |
| [`winn migrate`](#winn-migrate) | | Run database migrations |
| [`winn rollback`](#winn-rollback) | | Rollback migrations |
| [`winn task <name>`](#winn-task) | | Run a project task |
| [`winn add <package>`](#winn-add) | | Install a package |
| [`winn remove <package>`](#winn-remove) | | Remove a package |
| [`winn packages`](#winn-packages) | | List installed packages |
| [`winn install`](#winn-install) | | Install all from package.json |
| [`winn deps`](#winn-deps) | | Manage Erlang dependencies |
| [`winn bench <file>`](#winn-bench) | | Load testing |
| [`winn metrics`](#winn-metrics) | | Live metrics dashboard |
| [`winn release`](#winn-release) | | Build production release |
| [`winn version`](#winn-version) | `-v` | Print version |
| `winn help` | `-h` | Show help |

---

## Command Details

<a id="winn-new"></a>
### `winn new <name> [--api | --minimal]`

Create a new project. Three modes available:

```sh
winn new my_app              # full scaffold (default)
winn new my_app --api        # API project with router + health endpoint
winn new my_app --minimal    # just src/ and rebar.config
```

**Default** creates: `src/`, `test/`, `config/`, `db/migrations/`, `README.md`, `.env.example`, `.gitignore`, `package.json`.

**`--api`** adds a router with `use Winn.Router`, a `/api/health` endpoint, a health controller, and `Server.start` in `main()`.

**`--minimal`** creates only `src/<name>.winn`, `rebar.config`, `.gitignore`, and `package.json`.

<a id="winn-compile"></a>
### `winn compile [file]`

Compile `.winn` files to `.beam` bytecode in `ebin/`.

```sh
winn compile                   # all files in src/
winn compile src/my_app.winn   # single file
```

<a id="winn-run"></a>
### `winn run <file>`

Compile and run a single file. Calls `main()` and exits.

```sh
winn run src/hello.winn
```

<a id="winn-start"></a>
### `winn start [module]`

Compile all files, start OTP apps, call `main()`, keep the VM alive. Use for servers and long-running services.

```sh
winn start              # auto-detect main module
winn start my_app       # specify module
```

<a id="winn-test"></a>
### `winn test [file]`

Run tests written with `use Winn.Test`. Discovers `test_*` functions automatically.

```sh
winn test                       # all tests in test/
winn test test/math_test.winn   # specific file
```

```winn
module MathTest
  use Winn.Test

  def test_addition()
    assert(1 + 1 == 2)
  end

  def test_equality()
    assert_equal("hello", "hello")
  end
end
```

<a id="winn-watch"></a>
### `winn watch`

Watch files for changes, hot-reload via BEAM code swap, show a live terminal dashboard.

```sh
winn watch              # watch and recompile
winn watch --start      # watch + start the app
```

<a id="winn-create"></a>
### `winn create <type>` / `winn c`

Generate code from templates. `winn c` is shorthand.

```sh
winn create model User name:string email:string
# => src/models/user.winn

winn create migration CreateUsers name:string
# => db/migrations/TIMESTAMP_create_users.winn

winn create task db:seed
# => src/tasks/db_seed.winn

winn create router Api
# => src/controllers/api_controller.winn  (module ApiController)

winn create scaffold Post title:string body:text
# => src/models/post.winn, src/controllers/post_controller.winn, test/post_test.winn
```

Scaffold generates model + CRUD controller + test file.

<a id="winn-migrate"></a>
### `winn migrate`

Run pending database migrations from `db/migrations/*.winn`.

```sh
winn migrate              # run all pending
winn migrate --step 2     # run next 2
winn migrate --status     # show applied vs pending
```

<a id="winn-rollback"></a>
### `winn rollback`

Rollback database migrations.

```sh
winn rollback             # rollback last
winn rollback --step 3    # rollback last 3
```

<a id="winn-task"></a>
### `winn task <name>`

Run project tasks. Rails-style colon syntax.

```sh
winn task db:seed
winn task db:migrate
```

Tasks are modules with `use Winn.Task` and a `run/1` function in `src/tasks/`.

<a id="winn-add"></a>
### `winn add <package>`

Install a Winn package.

```sh
winn add redis                        # from gregwinn/winn-redis
winn add github:user/winn-stripe      # from any GitHub repo
```

<a id="winn-remove"></a>
### `winn remove <package>`

Remove an installed package.

```sh
winn remove redis
```

<a id="winn-packages"></a>
### `winn packages`

List installed packages with version and module name.

<a id="winn-install"></a>
### `winn install`

Install all packages from `package.json`.

**Available packages:**

| Package | Install | Description |
|---------|---------|-------------|
| [winn-redis](https://github.com/gregwinn/winn-redis) | `winn add redis` | Redis client |
| [winn-mongodb](https://github.com/gregwinn/winn-mongodb) | `winn add mongodb` | MongoDB client |
| [winn-amqp](https://github.com/gregwinn/winn-amqp) | `winn add amqp` | RabbitMQ/AMQP client |

<a id="winn-fmt"></a>
### `winn fmt [file]`

Format Winn source files for consistent code style.

```sh
winn fmt                   # format all .winn files in src/ (or current dir)
winn fmt src/app.winn      # format a specific file
winn fmt --check           # check formatting without modifying (exits 1 if unformatted)
```

<a id="winn-lint"></a>
### `winn lint [file]`

Run static analysis on Winn source files.

```sh
winn lint                  # lint all .winn files in src/ (or current dir)
winn lint src/app.winn     # lint a specific file
```

**Rules checked:**

| Rule | Category | Description |
|------|----------|-------------|
| `unused_variable` | Correctness | Variable assigned but never referenced (prefix with `_` to ignore) |
| `unused_import` | Correctness | Import directive with no calls to that module |
| `unused_alias` | Correctness | Alias directive with no calls using that alias |
| `function_name_convention` | Style | Function names must be `snake_case` (trailing `?` allowed) |
| `module_name_convention` | Style | Module names must be PascalCase |
| `redundant_boolean` | Simplification | `x == true` can be simplified to `x` |
| `empty_function_body` | Correctness | Function with no body returns `nil` silently |
| `pipe_into_literal` | Correctness | Pipe `\|>` into a non-callable value |
| `single_pipe` | Style | Single `\|>` with no chain — consider a regular call |
| `large_function` | Complexity | Function body exceeds 50 expressions |

Exits with code 0 if no warnings, code 1 if warnings found.

<a id="winn-lsp"></a>
### `winn lsp`

Start the Language Server Protocol server on stdio. Provides IDE integration for editors that support LSP (VS Code, Neovim, Helix, etc.).

```sh
winn lsp   # starts language server on stdio
```

**Capabilities:**

- **Diagnostics** — inline compile errors from lexer, parser, semantic, and transform phases, plus lint warnings from `winn lint` (each warning carries its rule name in the LSP `code` field). Triggered on file open, change, and save; cleared on close.
- **Autocomplete** — dot-triggered completions for 14 modules: IO, String, Enum, List, Map, Server, HTTP, JSON, Logger, File, Repo, System, Task, Regex, Agent.

**VS Code integration:** In the [Winn VS Code extension](https://marketplace.visualstudio.com/items?itemName=gregwinn.language-winn-vscode), set `"winn.lsp.command": "winn lsp"`.

<a id="winn-docs"></a>
### `winn docs [file]`

Generate Markdown API docs with a Mermaid module dependency graph.

```sh
winn docs                 # all src/*.winn → doc/api/
winn docs src/api.winn    # single file
```

<a id="winn-bench"></a>
### `winn bench <file>`

Run load tests with concurrent BEAM workers. Reports P50/P95/P99 latency.

```sh
winn bench bench/api_bench.winn
```

<a id="winn-metrics"></a>
### `winn metrics`

Live terminal dashboard showing HTTP stats, BEAM health, and custom metrics.

<a id="winn-release"></a>
### `winn release`

Build a production OTP release.

```sh
winn release              # build release
winn release --docker     # generate Dockerfile
```

<a id="winn-deps"></a>
### `winn deps`

Manage Erlang dependencies (lower-level than `winn add`).

```sh
winn deps list
winn deps add cowboy 2.12.0
winn deps remove cowboy
winn deps install
```

<a id="winn-console"></a>
### `winn console`

Interactive REPL with variable persistence.

<a id="winn-version"></a>
### `winn version`

```sh
winn version    # => winn 0.7.0
winn -v
winn --version
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Compilation error, runtime error, or unknown command |

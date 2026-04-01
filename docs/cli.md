# Winn CLI

## Install

```sh
brew tap gregwinn/winn && brew install winn
```

## Quick Reference

| Command | Description |
|---------|-------------|
| [`winn new <name>`](#winn-new) | Create a new project |
| [`winn compile [file]`](#winn-compile) | Compile `.winn` files to `.beam` |
| [`winn run <file>`](#winn-run) | Compile and run a single file |
| [`winn start [module]`](#winn-start) | Start project (keeps VM alive) |
| [`winn test [file]`](#winn-test) | Run tests |
| [`winn watch [--start]`](#winn-watch) | Hot-reload with live dashboard |
| [`winn create <type>`](#winn-create) | Generate code (model, migration, task, router, scaffold) |
| [`winn c <type>`](#winn-create) | Shorthand for create |
| [`winn migrate`](#winn-migrate) | Run database migrations |
| [`winn rollback`](#winn-rollback) | Rollback migrations |
| [`winn task <name>`](#winn-task) | Run a project task |
| [`winn add <package>`](#winn-add) | Install a package |
| [`winn remove <package>`](#winn-remove) | Remove a package |
| [`winn packages`](#winn-packages) | List installed packages |
| [`winn install`](#winn-install) | Install all from package.json |
| [`winn docs [file]`](#winn-docs) | Generate API docs with Mermaid graph |
| [`winn bench <file>`](#winn-bench) | Run load tests |
| [`winn metrics`](#winn-metrics) | Live metrics dashboard |
| [`winn release`](#winn-release) | Build production release |
| [`winn deps`](#winn-deps) | Manage Erlang dependencies |
| [`winn console`](#winn-console) | Interactive REPL |
| [`winn version`](#winn-version) | Print version |

---

## Command Details

<a id="winn-new"></a>
### `winn new <name>`

Create a new project with `src/`, `rebar.config`, `package.json`, and `.gitignore`.

```sh
winn new my_app
```

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
winn create migration CreateUsers name:string
winn create task db:seed
winn create router Api
winn create scaffold Post title:string body:text
```

Scaffold generates model + CRUD router + test file.

<a id="winn-migrate"></a>
### `winn migrate`

Run pending database migrations from `migrations/*.winn`.

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

Tasks are modules with `use Winn.Task` and a `run/1` function in `tasks/` or `src/`.

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

# Winn

Winn is a Ruby/Elixir-inspired language that compiles to the BEAM (Erlang VM). It combines Ruby's readable syntax with Elixir's pipe operator, pattern matching, and OTP concurrency primitives.

## Features

- **Clean syntax** — `module`, `def`, `end` keywords; no noise
- **String interpolation** — `"Hello, #{name}!"`
- **Pipe operator** — `|>` for composable data transformations
- **Pattern matching** — multi-clause functions, `match...end` blocks, destructuring assignment
- **Closures** — `do |x| ... end` blocks and standalone `fn(x) => expr end` lambdas
- **Control flow** — `if/else`, `switch` (with multi-line `do...end` bodies), guards (`when`), `try/rescue`
- **For comprehensions** — `for x in 1..10 do x * 2 end`
- **Range literals** — `1..100`
- **Map field access** — `user.name` instead of `Map.get(:name, user)`
- **OTP integration** — `use Winn.GenServer` / `use Winn.Supervisor` / `use Winn.Application`
- **Built-in ORM** — schema DSL, changesets, Repo, PostgreSQL via epgsql
- **HTTP server** — Cowboy-powered with routing, middleware, JSON responses
- **HTTP client** — `HTTP.get/post/put/patch/delete` with auto JSON
- **JWT** — pure Erlang HS256 sign/verify
- **WebSockets** — client via gun (`WS.connect/send/recv/close`)
- **Async tasks** — `Task.async/await/async_all` for easy concurrency
- **Structured logging** — `Logger.info/warn/error/debug` with JSON output
- **Crypto** — hashing, HMAC, random bytes, base64
- **JSON** — `JSON.encode/decode`
- **Config** — ETS-backed config with `Config.get/put/load`
- **Testing framework** — `winn test` with `assert`/`assert_equal`, test discovery
- **Import/alias** — `import Enum` for unqualified calls, `alias MyApp.Auth` for short names
- **Doc generator** — `winn docs` generates Markdown API docs with Mermaid dependency graphs
- **File watcher** — `winn watch` with hot code reloading and live terminal dashboard
- **Clear error messages** — source context, caret pointers, hints
- **Compiles to BEAM** — runs on the battle-tested Erlang virtual machine

## Install

### Homebrew (macOS)

```sh
brew tap gregwinn/winn
brew install winn
```

Requires Erlang/OTP 28+ (installed automatically by Homebrew if needed).

### From Source

```sh
git clone https://github.com/gregwinn/winn-lang.git
cd winn-lang
rebar3 escriptize
cp _build/default/bin/winn /usr/local/bin/
```

### Verify

```sh
winn version
# => winn 0.3.2
```

## Quick Start

```sh
# Create a new project
winn new my_app
cd my_app

# Run it
winn run src/my_app.winn

# Or compile and start (keeps VM alive for servers)
winn start
```

### Hello World

Create `hello.winn`:

```winn
module Hello
  def main()
    name = "World"
    IO.puts("Hello, #{name}!")
  end
end
```

```sh
winn run hello.winn
# => Hello, World!
```

## Language Overview

```winn
module Greeter
  def greet(name)
    "Hello, #{name}!"
  end

  def greet(:world)
    "Hello, World!"
  end
end
```

```winn
module Pipeline
  def main()
    1..10
      |> Enum.filter() do |x| x > 5 end
      |> Enum.map() do |x| x * 100 end
      |> Enum.join(", ")
      |> IO.puts()
  end
end
```

```winn
module Example
  def classify(n)
    switch n
      x when x > 0 => :positive
      x when x < 0 => :negative
      _             => :zero
    end
  end

  def main()
    {:ok, data} = fetch_data()

    results = for item in data do
      item.name
    end

    doubled = fn(x) => x * 2 end
    IO.puts("#{to_string(doubled(21))}")
  end
end
```

```winn
module Api
  use Winn.Router

  def routes()
    [{:get, "/users/:id", :get_user}]
  end

  def middleware()
    [:log_request]
  end

  def log_request(conn, next)
    Logger.info("#{Server.method(conn)} #{Server.path(conn)}")
    next(conn)
  end

  def get_user(conn)
    id = Server.path_param(conn, "id")
    Server.json(conn, %{id: id})
  end
end
```

## Project Structure

```
language-winn/
├── apps/winn/src/
│   ├── winn_lexer.xrl       # leex tokenizer
│   ├── winn_parser.yrl      # yecc LALR(1) grammar
│   ├── winn_transform.erl   # AST desugaring (pipes, patterns, blocks, schemas)
│   ├── winn_semantic.erl    # scope analysis
│   ├── winn_codegen.erl     # Core Erlang code generation
│   ├── winn_core_emit.erl   # Core Erlang -> .beam
│   ├── winn_errors.erl      # human-readable compiler error formatting
│   ├── winn_runtime.erl     # stdlib (IO, String, Enum, List, Map, System, UUID, DateTime)
│   ├── winn_logger.erl      # structured JSON logging
│   ├── winn_crypto.erl      # hashing, HMAC, base64
│   ├── winn_json.erl        # JSON encode/decode
│   ├── winn_server.erl      # HTTP server runtime (cowboy)
│   ├── winn_router.erl      # HTTP route matching, dispatch, middleware
│   ├── winn_http.erl        # HTTP client (hackney + jsone)
│   ├── winn_jwt.erl         # JWT sign/verify (pure Erlang HS256)
│   ├── winn_task.erl        # async/await concurrency
│   ├── winn_ws.erl          # WebSocket client (gun)
│   ├── winn_config.erl      # ETS-backed configuration
│   ├── winn_repo.erl        # ORM database layer
│   ├── winn_changeset.erl   # changeset validation
│   ├── winn_test.erl        # testing framework (assert, test runner)
│   ├── winn_docs.erl        # documentation generator + Mermaid graphs
│   ├── winn_watch.erl       # file watcher with live terminal dashboard
│   ├── winn_cli.erl         # CLI escript (new/compile/run/start/test/docs/watch/version/help)
│   └── winn.erl             # public API
├── apps/winn/test/           # 360 tests across 26 test files
└── docs/
    ├── getting-started.md    # install, create, build, run
    ├── language.md           # syntax reference
    ├── stdlib.md             # standard library
    ├── otp.md                # GenServer / Supervisor / Application
    ├── orm.md                # Schema / Repo / Changeset
    ├── modules.md            # HTTP server/client, JWT, WebSockets, Tasks, Config
    └── cli.md                # CLI commands
```

## Documentation

- **[Getting Started](docs/getting-started.md)** — install, create a project, build, and run
- [Language Guide](docs/language.md) — syntax, control flow, pattern matching, interpolation, lambdas, ranges
- [Standard Library](docs/stdlib.md) — IO, String, Enum, List, Map, System, UUID, DateTime, Logger, Crypto, JSON
- [OTP Integration](docs/otp.md) — GenServer, Supervisor, Application
- [ORM](docs/orm.md) — Schema, Repo, Changeset
- [Modules](docs/modules.md) — HTTP server/client, JWT, WebSockets, Tasks, Config
- [CLI Reference](docs/cli.md) — all CLI commands

## Editor Support

- [VS Code extension](https://github.com/gregwinn/language-winn-vscode) — syntax highlighting + compile-on-save diagnostics

# Winn

Winn is a Ruby/Elixir-inspired language that compiles to the BEAM (Erlang VM). It combines Ruby's readable syntax with Elixir's pipe operator, pattern matching, and OTP concurrency primitives.

## Features

- **Clean syntax** — `module`, `def`, `end` keywords; no noise
- **Pipe operator** — `|>` for composable data transformations
- **Pattern matching** — multi-clause functions and `match...end` blocks
- **Closures** — `do |x| ... end` blocks passed to iterators
- **Control flow** — `if/else`, `switch`, guards (`when`), `try/rescue`
- **OTP integration** — `use Winn.GenServer` / `use Winn.Supervisor` / `use Winn.Application`
- **Built-in ORM** — schema DSL, changesets, Repo, PostgreSQL via epgsql
- **HTTP server** — Cowboy-powered with route matching, JSON responses, path/query params
- **HTTP client** — `HTTP.get/post/put/patch/delete` with auto JSON
- **JWT** — pure Erlang HS256 sign/verify
- **WebSockets** — client via gun (`WS.connect/send/recv/close`)
- **Async tasks** — `Task.async/await/async_all` for easy concurrency
- **Structured logging** — `Logger.info/warn/error/debug` with JSON output
- **Crypto** — hashing, HMAC, random bytes, base64
- **Config** — ETS-backed config with `Config.get/put/load`
- **Compiles to BEAM** — runs on the battle-tested Erlang virtual machine

## Quick Start

### Prerequisites

- Erlang/OTP 28+
- rebar3

### Build

```sh
git clone <repo>
cd language-winn
rebar3 compile
```

### Run Tests

```sh
rebar3 eunit
# => 238 tests, 0 failures
```

### Hello World

Create `hello.winn`:

```winn
module Hello
  def main()
    IO.puts("Hello, World!")
  end
end
```

Compile and run:

```sh
./_build/default/bin/winn run hello.winn
```

Or from the rebar3 shell:

```sh
rebar3 shell
> winn:compile_file("hello.winn", "/tmp").
> hello:main().
Hello, World!
```

## Language Overview

```winn
module Greeter
  def greet(name)
    "Hello, " <> name <> "!"
  end

  def greet(:world)
    "Hello, World!"
  end
end
```

```winn
module Pipeline
  def process(list)
    list
      |> Enum.filter() do |x| x > 0 end
      |> Enum.map()    do |x| x * 2 end
  end
end
```

```winn
module Example
  def classify(n)
    if n > 0
      :positive
    else
      switch n
        0 => :zero
        _ => :negative
      end
    end
  end

  def safe_divide(a, b) when b != 0
    a / b
  end

  def safe_divide(_, 0)
    {:error, "division by zero"}
  end
end
```

```winn
module WebService
  def fetch_user(id)
    try
      HTTP.get("https://api.example.com/users/" <> id)
    rescue
      _ => {:error, :network_failure}
    end
  end

  def create_token(user_id)
    secret = System.get_env("JWT_SECRET")
    JWT.sign(%{user_id: user_id}, secret)
  end
end
```

```winn
module Post
  use Winn.Schema

  schema "posts" do
    field :title, :string
    field :body,  :text
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
│   ├── winn_runtime.erl     # stdlib (IO, String, Enum, List, Map, System, UUID, DateTime)
│   ├── winn_logger.erl      # structured JSON logging
│   ├── winn_crypto.erl      # hashing, HMAC, base64
│   ├── winn_server.erl      # HTTP server runtime (cowboy)
│   ├── winn_router.erl      # HTTP route matching + dispatch
│   ├── winn_http.erl        # HTTP client (hackney + jsone)
│   ├── winn_jwt.erl         # JWT sign/verify (pure Erlang HS256)
│   ├── winn_task.erl        # async/await concurrency
│   ├── winn_ws.erl          # WebSocket client (gun)
│   ├── winn_config.erl      # ETS-backed configuration
│   ├── winn_repo.erl        # ORM database layer
│   ├── winn_changeset.erl   # changeset validation
│   ├── winn_cli.erl         # CLI escript (new/compile/run/help)
│   └── winn.erl             # public API
├── apps/winn/test/           # 238 tests across 20 test files
└── docs/
    ├── language.md           # syntax reference
    ├── stdlib.md             # standard library
    ├── otp.md                # GenServer / Supervisor / Application
    ├── orm.md                # Schema / Repo / Changeset
    ├── modules.md            # HTTP, JWT, WebSockets, Tasks, Config
    └── cli.md                # CLI commands
```

## Documentation

- [Language Guide](docs/language.md) — syntax, control flow, pattern matching
- [Standard Library](docs/stdlib.md) — IO, String, Enum, List, Map, System, UUID, DateTime, Logger, Crypto
- [OTP Integration](docs/otp.md) — GenServer, Supervisor, Application
- [ORM](docs/orm.md) — Schema, Repo, Changeset
- [Modules](docs/modules.md) — HTTP, JWT, WebSockets, Tasks, Config
- [CLI](docs/cli.md) — CLI commands

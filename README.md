# Winn

Winn is a Ruby/Elixir-inspired language that compiles to the BEAM (Erlang VM). It combines Ruby's readable syntax with Elixir's pipe operator, pattern matching, and OTP concurrency primitives.

## Features

- **Clean syntax** — `module`, `def`, `end` keywords; no noise
- **Pipe operator** — `|>` for composable data transformations
- **Pattern matching** — multi-clause functions and `match...end` blocks
- **Closures** — `do |x| ... end` blocks passed to iterators
- **OTP integration** — `use Winn.GenServer` / `use Winn.Supervisor`
- **Built-in ORM** — schema DSL, changesets, Repo, PostgreSQL via epgsql
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
rebar3 shell
> winn:compile_file("hello.winn", "/tmp").
> hello:main().
Hello, World!
```

Or with the CLI (after `rebar3 escriptize`):

```sh
./_build/default/bin/winn run hello.winn
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
│   ├── winn_core_emit.erl   # Core Erlang → .beam
│   ├── winn_runtime.erl     # stdlib (IO, String, Enum, List, Map)
│   ├── winn_repo.erl        # ORM database layer
│   ├── winn_changeset.erl   # changeset validation
│   └── winn.erl             # public API
├── apps/winn/test/
│   ├── winn_lexer_tests.erl
│   ├── winn_parser_tests.erl
│   ├── winn_phase2_tests.erl
│   ├── winn_phase3_tests.erl
│   ├── winn_phase4_tests.erl
│   └── winn_phase5_tests.erl
└── docs/
    ├── language.md          # syntax reference
    ├── stdlib.md            # standard library
    ├── otp.md               # GenServer / Supervisor
    ├── orm.md               # Schema / Repo / Changeset
    └── cli.md               # CLI commands
```

## Documentation

- [Language Guide](docs/language.md)
- [Standard Library](docs/stdlib.md)
- [OTP Integration](docs/otp.md)
- [ORM](docs/orm.md)
- [CLI](docs/cli.md)

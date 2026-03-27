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

The generated `src/my_app.winn`:

```winn
module MyApp
  def main()
    IO.puts("Hello from MyApp!")
  end
end
```

The generated `rebar.config`:

```erlang
{erl_opts, [debug_info]}.
{deps, []}.
```

---

### `winn compile [file]`

Compile `.winn` files to `.beam` bytecode.

```sh
# Compile a single file — output to ebin/
winn compile src/my_app.winn

# Compile all .winn files in the current directory
winn compile
```

Output `.beam` files are written to `ebin/`. The directory is created automatically if it doesn't exist.

**What happens during compilation:**

1. Lexer tokenizes the source (`.winn` → tokens)
2. Parser builds the AST (tokens → syntax tree)
3. Semantic analysis checks scope and variables
4. Transform desugars pipes, match blocks, closures, schemas
5. Codegen produces Core Erlang via the `cerl` module
6. Core Erlang is compiled to `.beam` bytecode

**Error output:**

If compilation fails, you get a structured error message pointing to the issue:

```
-- Syntax Error ----------------------------- src/app.winn --

3 |     x +
4 |   end
  |   ^^^
5 | end
  Unexpected 'end'.
  Hint: Did you close a block too early, or forget an expression?
```

Errors are printed to stderr. The exit code is 1 on failure, 0 on success.

---

### `winn run <file>`

Compile a `.winn` file and immediately run it by calling `Module:main()`.

```sh
winn run src/hello.winn
```

How it works:

1. Compiles the file to a temporary directory
2. Loads the `.beam` into the running Erlang VM
3. Calls `module_name:main()` (falls back to `main/1` with `[]`)
4. Cleans up the temp directory

The module name is derived from the filename: `hello.winn` → calls `hello:main()`.

---

### `winn help`

Print usage information.

```sh
winn help
```

---

## Running Compiled Modules

After compiling with `winn compile`, run your BEAM files with Erlang directly:

```sh
# Simple — just your compiled code
erl -pa ebin -noshell -eval 'my_app:main(), halt().'

# With dependencies (HTTP server, etc.)
erl -pa ebin -pa _build/default/lib/*/ebin -noshell -eval 'my_app:main().'
```

---

## Typical Workflow

```sh
# 1. Create a new project
winn new my_app
cd my_app

# 2. Edit your source files
#    (use VS Code with the Winn extension for syntax highlighting)

# 3. Compile
winn compile src/my_app.winn

# 4. Run
winn run src/my_app.winn

# Or compile all and run with Erlang
winn compile
erl -pa ebin -noshell -eval 'my_app:main(), halt().'
```

---

## Programmatic API

You can also drive the Winn compiler from Erlang code or the rebar3 shell:

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

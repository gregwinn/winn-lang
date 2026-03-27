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

### `winn version`

Print the version.

```sh
winn version
# => winn 0.2.0

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

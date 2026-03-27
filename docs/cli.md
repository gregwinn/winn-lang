# Winn CLI

The `winn` command-line tool provides commands for creating, compiling, and running Winn programs.

## Installation

Build the escript binary:

```sh
rebar3 escriptize
```

This produces `./_build/default/bin/winn`. Add it to your PATH:

```sh
export PATH="$PATH:/path/to/language-winn/_build/default/bin"
```

## Commands

### `winn new <name>`

Scaffold a new Winn project.

```sh
winn new my_app
```

Creates:

```
my_app/
├── rebar.config
├── .gitignore
└── src/
    └── my_app.winn
```

The generated `src/my_app.winn`:

```winn
module MyApp
  def main()
    IO.puts("Hello from MyApp!")
  end
end
```

---

### `winn compile [file_or_dir]`

Compile `.winn` files to `.beam` bytecode in `ebin/`.

```sh
# Compile a single file
winn compile src/my_app.winn

# Compile all .winn files in src/
winn compile
```

Output `.beam` files are written to `ebin/`.

---

### `winn run <file>`

Compile and immediately run a Winn file. Calls `Module:main()`.

```sh
winn run hello.winn
```

The module name is derived from the filename (`hello.winn` → module `hello`). If the module defines `main/0` it is called automatically.

---

### `winn help`

Print usage information.

```sh
winn help
```

## Erlang API

You can also drive the compiler from Erlang/the rebar3 shell:

```erlang
%% Compile a file, write .beam to a directory
winn:compile_file("src/hello.winn", "ebin").

%% Compile a string directly
winn:compile_string("Hello", "def main() IO.puts(\"hi\") end", "ebin").
```

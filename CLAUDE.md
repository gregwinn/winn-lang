# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workflow Rules

- **Branch per feature.** Every new feature or change must be developed on its own branch off `develop`. Never commit directly to `main` or `develop`. Use descriptive branch names: `feature/repl`, `fix/scaffold-module-name`, `docs/update-cli`.
- **Document everything.** Every new or updated feature must be documented before merging. Update the relevant docs in `docs/` (language.md, stdlib.md, modules.md, cli.md, getting-started.md) and add a CHANGELOG.md entry. If it changes syntax, update the VS Code grammar in the separate `language-winn-vscode` repo. If it adds a CLI command, update the help text in `winn_cli.erl`.

## Build & Test Commands

```sh
rebar3 compile              # Compile everything
rebar3 eunit                # Run all 502 tests
rebar3 eunit --module=winn_l1_tests  # Run a single test module
rebar3 escriptize           # Build the winn CLI escript
./_build/default/bin/winn help       # Verify CLI works
```

## Compiler Pipeline

Source flows through 6 stages in `winn.erl:run_pipeline/3`:

```
winn_lexer.xrl → winn_parser.yrl → winn_semantic → winn_transform → winn_codegen → winn_core_emit
   (leex)          (yecc)           (scope check)   (desugar)        (Core Erlang)   (.beam)
```

Each stage returns `{ok, Value}` or `{error, Reason}`, chained via `with/1`. Errors are formatted by `winn_errors.erl` and printed to stderr. Transform and codegen stages are wrapped in try/catch in `winn.erl` to convert crashes into structured error tuples.

## AST Convention

All AST nodes are tagged tuples: `{Tag, Line, ...fields}`. No records. Key shapes:

- Module: `{module, Line, Name, Body}`
- Function: `{function, Line, Name, Params, Body}` / `{function_g, Line, Name, Params, Guard, Body}`
- Calls: `{call, L, Fun, Args}` / `{dot_call, L, Mod, Fun, Args}`
- Patterns: `{pat_tuple, L, Elems}`, `{pat_atom, L, Val}`, `{pat_var, L, Name}`, `{pat_wildcard, L}`
- Control: `{if_expr, L, Cond, Then, Else}`, `{switch_expr, L, Scrutinee, Clauses}`, `{try_expr, L, Body, Rescues}`

## Transform (Desugaring) Order

`winn_transform.erl` runs these passes in sequence:

1. **Use directives** → behaviour attributes + synthetic functions (GenServer gets `start_link/1`)
2. **Import/alias extraction** → builds import list and alias map from directives
3. **Schema defs** → generated `__schema__/1` and `new/1` functions
4. **All functions case-wrapped** → even simple-var params get wrapped so guarded + non-guarded clauses merge
5. **Multi-clause merge** → adjacent same-name/arity functions become one function with case clauses
6. **Expression desugaring** → pipes flattened, match blocks → case, interpolation → `<>` chains, `for` → `Enum.map`
7. **Import/alias rewriting** → local calls rewritten to dot calls (import), short module names expanded (alias)

## Module Name Mapping (Codegen)

`winn_codegen.erl:resolve_dot_call/2` maps Winn module calls to Erlang:

- `IO/String/Enum/List/Map` → `winn_runtime` with dotted atom names (`'io.puts'`, `'enum.map'`)
- `System/UUID/DateTime` → `winn_runtime` with dotted atoms
- `Logger` → `winn_logger`, `Crypto` → `winn_crypto`, `JSON` → `winn_json`
- `HTTP` → `winn_http`, `Server` → `winn_server`, `Config` → `winn_config`
- `Task` → `winn_task`, `JWT` → `winn_jwt`, `WS` → `winn_ws`
- `GenServer` → `gen_server`, `Supervisor` → `supervisor` (direct OTP)
- `Winn` → `winn_runtime` (for `to_string` in interpolation)
- Fallback: lowercase the module name

To add a new Winn module: create `winn_newmod.erl`, add a `resolve_dot_call` clause.

## Builtin Function Detection

`to_string`, `to_integer`, `to_float`, `to_atom`, and `inspect` are detected in codegen as local calls and routed to `winn_runtime`. `assert` and `assert_equal` are routed to `winn_test`.

## Variable Scoping in Codegen

`gen_body/1` handles assignment scoping: `{assign, _, {var,_,Name}, Expr}` becomes `cerl:c_let` (not `c_seq`) so bindings scope over subsequent expressions. Pattern assignments (`pat_assign_case`) emit a `c_case` that scopes pattern variables over the rest of the body.

## Test Pattern

Tests compile Winn source strings end-to-end and execute:

```erlang
compile_and_load(Source) ->
    {ok, Tokens, _} = winn_lexer:string(Source),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.
```

Use unique module names in each test to avoid beam cache collisions.

## Parser Constraints

- Switch and rescue clause bodies are **single expressions** unless wrapped in `do...end` (no newline tokens)
- The `%` token requires `\%` escaping in the leex `.xrl` file
- `ok` and `err` are reserved keywords (`ok_kw`, `err_kw`) — cannot be used as map keys or identifiers
- Shift/reduce conflicts exist (currently ~52) but 0 reduce/reduce

## Naming Conventions

- Winn module names: PascalCase → compile to lowercase atoms (`HelloWorld` → `helloworld`)
- Dotted module names: `module MyApp.Router` → atom `'myapp.router'`
- Module names as values: PascalCase atoms are lowercased in codegen (`Post` → `post`)
- Function names can end with `?` for predicates (`contains?`, `valid?`)
- Runtime functions: dotted atoms (`'io.puts'`, `'enum.map'`)
- Variables: Core Erlang requires uppercase, so codegen capitalizes first char (`x` → `X`)
- Pattern nodes use `pat_` prefix: `pat_tuple`, `pat_atom`, `pat_var`, `pat_wildcard`

## CLI (winn_cli.erl)

Commands: `new`, `compile`, `run`, `start`, `test`, `docs`, `watch`, `create`/`c`, `task`, `migrate`, `rollback`, `release`, `bench`, `metrics`, `console`, `deps`, `version`, `help`. The `start` command compiles all `src/*.winn`, loads `_build` dep paths, starts OTP apps, calls `main()`, and blocks with `receive` to keep the VM alive. The `run` command reads the module name from the source file (regex on `module Name`), not from the filename.

## Release Process

Use `/release patch|minor|major` Claude skill, or manually:
1. Bump version in `apps/winn/src/winn.app.src`, `winn_cli.erl`, and `winn_repl.erl` fallbacks
2. `rebar3 escriptize`
3. Tag, push, `gh release create`
4. Update `gregwinn/homebrew-winn` Formula with new URL + SHA256
5. **Update `gregwinn/winn-lang-website`** — version in footer, features, code examples, roadmap (CRITICAL)

## External Dependencies

- `epgsql` — PostgreSQL driver (ORM)
- `hackney` — HTTP client
- `jsone` — JSON encode/decode
- `gun` — WebSocket client
- `cowboy` — HTTP server (also provides `cowlib`, `ranch`)

# Winn Roadmap

## Current Status — v0.8.1

Homebrew install (`brew install gregwinn/winn/winn`). VS Code extension with syntax highlighting and compile-on-save diagnostics.

### What's Shipped

| Version | Theme | Highlights |
|---------|-------|------------|
| v0.1.0 | Core Language | Modules, functions, pattern matching, pipes, closures, if/else, switch, guards, try/rescue |
| v0.2.0 | Runtime | String interpolation, lambdas, for comprehensions, ranges, HTTP server/client, ORM, CLI |
| v0.3.0 | Developer Experience | `winn test`, `import`/`alias`, `winn docs` with Mermaid graphs, `winn watch` live dashboard |
| v0.4.0 | Language Power | Pipe assign (`\|>=`), triple-quoted strings, default params, structs, protocols, significant newlines, block comments |
| v0.5.0 | Production Readiness | Connection pooling, transactions, SQLite, model methods (`User.all`), migrations, generators (`winn create`), deployment |
| v0.6.0 | Observability | Metrics module, live metrics dashboard (`winn metrics`), load testing (`winn bench`) |
| v0.7.0 | Core Stdlib + Packages | File I/O, Regex, Timer, Retry, DateTime/String, package system (`winn add`/`winn remove`), [winn-redis](https://github.com/gregwinn/winn-redis), [winn-mongodb](https://github.com/gregwinn/winn-mongodb), [winn-amqp](https://github.com/gregwinn/winn-amqp) |
| v0.8.0 | Web Framework + Agents | Static files, CORS, auth middleware, health checks, `agent` keyword with `@state` syntax and `async def`, compiles to GenServer |
| v0.8.1 | Bug Fix | Fixed agent parser regression (stale committed `winn_parser.erl`); CI cache now busts on grammar changes |

---

## Coming Next

### v0.9.0 — Developer Tooling

| Issue | Feature | Description |
|-------|---------|-------------|
| [#52](https://github.com/gregwinn/winn-lang/issues/52) | Formatter | `winn fmt` for consistent code style |
| [#53](https://github.com/gregwinn/winn-lang/issues/53) | Linter | `winn lint` for static analysis |
| [#54](https://github.com/gregwinn/winn-lang/issues/54) | Scaffold | Improved `winn new` with test/, config/ |
| [#114](https://github.com/gregwinn/winn-lang/issues/114) | Generator dirs | Rails-style subdirectories: `src/models/`, `src/controllers/`, `db/migrations/` |
| [#55](https://github.com/gregwinn/winn-lang/issues/55) | LSP | Language server for IDE integration |
| [#99](https://github.com/gregwinn/winn-lang/issues/99) | Codegen split | Split `winn_codegen.erl` into focused submodules |

### v0.10.0 — Hardening

| Issue | Feature | Description |
|-------|---------|-------------|
| [#56](https://github.com/gregwinn/winn-lang/issues/56) | Compiler errors | Better error handling for edge cases |
| [#57](https://github.com/gregwinn/winn-lang/issues/57) | Validators | Extended changeset validators |
| [#58](https://github.com/gregwinn/winn-lang/issues/58) | Bounds checking | Safe defaults for runtime functions |
| [#98](https://github.com/gregwinn/winn-lang/issues/98) | Parser conflicts | Resolve shift/reduce conflicts before v1.0 |
| [#100](https://github.com/gregwinn/winn-lang/issues/100) | Transform hardening | Pass ordering tests and invariant docs |

### v1.0.0 — The Winn Platform

| Issue | Feature | Description |
|-------|---------|-------------|
| [#32](https://github.com/gregwinn/winn-lang/issues/32) | AI Pipelines | `AI.chat()`, `AI.classify()`, `AI.extract()` as stdlib, Agent DSL, Smart Pipes |
| [#33](https://github.com/gregwinn/winn-lang/issues/33) | Distributed Events | `Event.emit` / `on :event do` across BEAM nodes, zero infrastructure |
| [#34](https://github.com/gregwinn/winn-lang/issues/34) | Background Jobs | `use Winn.Job` with queues, retries, cron, live dashboard |
| [#103](https://github.com/gregwinn/winn-lang/issues/103) | **Reactive events** | Language-level `on`/`emit` pub/sub built on BEAM distribution |
| [#104](https://github.com/gregwinn/winn-lang/issues/104) | **Pipelines** | `pipeline` keyword — supervised multi-stage data flows with backpressure |
| [#108](https://github.com/gregwinn/winn-lang/issues/108) | **Distributed clustering** | `Winn.connect(:node@host)` — agents, events, and pipelines auto-span nodes |

### Ecosystem

| Issue | Feature | Description |
|-------|---------|-------------|
| [#20](https://github.com/gregwinn/winn-lang/issues/20) | Example projects | Todo API, chat server, GitHub sync worker |
| [#21](https://github.com/gregwinn/winn-lang/issues/21) | Package registry | Hosted Winn-native registry, `winn publish`, search, discovery |
| [#101](https://github.com/gregwinn/winn-lang/issues/101) | Package registry v2 | Dependency resolution, lockfile, `winn search` |
| [#110](https://github.com/gregwinn/winn-lang/issues/110) | curl installer | `curl -fsSL https://winn.ws/install.sh \| bash` — detect OS/arch, install pre-built binary |
| [#111](https://github.com/gregwinn/winn-lang/issues/111) | apt + dnf packages | Native `.deb`/`.rpm` packages with hosted repos and GPG signing for Ubuntu and Fedora |

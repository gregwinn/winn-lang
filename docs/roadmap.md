# Winn Roadmap

## Current Status — v0.9.5

648 tests. Homebrew install (`brew install gregwinn/winn/winn`). VS Code extension with syntax highlighting and compile-on-save diagnostics. LSP with inline errors and autocomplete.

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
| v0.9.0 | Developer Tooling | `winn fmt`, `winn lint` (10 rules), `winn lsp` (diagnostics + autocomplete), improved `winn new` (--api, --minimal), command shortcuts, codegen split |
| v0.9.1 | Bug fix | `Repo.configure` binary host crashing epgsql connect ([#145](https://github.com/gregwinn/winn-lang/issues/145)) |
| v0.9.2 | Bug fix | `winn_pool` race: trap exits from failed epgsql connects + release infra nfpm URL fix |
| v0.9.3 | Bug fix | Repeated `_` wildcard in a function head rejected by `core_lint` ([#170](https://github.com/gregwinn/winn-lang/issues/170)) |
| v0.9.4 | Bug fix | Configurable HTTP client timeouts ([#184](https://github.com/gregwinn/winn-lang/issues/184)) + apt index regeneration |
| v0.9.5 | Bug fix | `winn create model` / `scaffold` generated non-compiling models ([#183](https://github.com/gregwinn/winn-lang/issues/183)) |

### Install Methods

| Method | Command | Issue |
|--------|---------|-------|
| Homebrew | `brew install gregwinn/winn/winn` | — |
| curl installer | `curl -fsSL https://winn.ws/install.sh \| bash` | [#110](https://github.com/gregwinn/winn-lang/issues/110) |
| apt (Debian/Ubuntu) | `.deb` published to the hosted apt repo each release | [#111](https://github.com/gregwinn/winn-lang/issues/111) |
| dnf (Fedora/RHEL) | `.rpm` attached to each release | [#111](https://github.com/gregwinn/winn-lang/issues/111) |
| From source | `rebar3 escriptize` | — |

---

## Merged on `develop` — ships as v0.10.0

Complete and merged, awaiting the release cut. See the CHANGELOG `[Unreleased]` section.

| Issue | Feature | Description |
|-------|---------|-------------|
| [#161](https://github.com/gregwinn/winn-lang/issues/161) | **Authentication** | Email/password auth: PBKDF2 hashing ([#162](https://github.com/gregwinn/winn-lang/issues/162)), `Auth` service ([#163](https://github.com/gregwinn/winn-lang/issues/163)), revocable refresh tokens ([#164](https://github.com/gregwinn/winn-lang/issues/164)), cookie sessions + CSRF ([#165](https://github.com/gregwinn/winn-lang/issues/165)), `Mailer` ([#166](https://github.com/gregwinn/winn-lang/issues/166)), account recovery ([#167](https://github.com/gregwinn/winn-lang/issues/167)), `winn create auth` scaffold ([#168](https://github.com/gregwinn/winn-lang/issues/168)) — [guide](auth.md) |
| [#104](https://github.com/gregwinn/winn-lang/issues/104) | **Pipelines** | `pipeline` keyword — Broadway-shape producer/processor/batcher with prefetch backpressure and supervised drain (accelerated from v1.0 for Echolo `fleet_delivery`) |
| [#98](https://github.com/gregwinn/winn-lang/issues/98) | Parser conflicts | Operator precedence declared in `winn_parser.yrl`; shift/reduce 53 → 3. Chained comparisons are now a parse error (**breaking**) |
| [#58](https://github.com/gregwinn/winn-lang/issues/58) | Bounds checking | Safe defaults for runtime functions. `List.first/last` on `[]` return `nil` (**breaking**) |
| [#156](https://github.com/gregwinn/winn-lang/issues/156) | Prometheus metrics | `Metrics.prometheus()` — v0.0.4 text exposition format |
| [#157](https://github.com/gregwinn/winn-lang/issues/157) | String escapes | `\"`, `\\`, `\n`, `\r`, `\t`, `\0` in double-quoted strings |
| [#128](https://github.com/gregwinn/winn-lang/issues/128) | Private functions | `private def` — excluded from the module export list |
| [#118](https://github.com/gregwinn/winn-lang/issues/118) / [#119](https://github.com/gregwinn/winn-lang/issues/119) | LSP phases 1–2 | Lint diagnostics; document symbols, hover, go-to-definition |
| [#153](https://github.com/gregwinn/winn-lang/issues/153) | Deployment guide | [docs/deployment.md](deployment.md) — sizing, logging, metrics, graceful shutdown, k8s |
| [#172](https://github.com/gregwinn/winn-lang/issues/172) | Repo row mapping | Map result rows by DB column metadata, not the schema field list |

---

## Coming Next

### v0.10.0 — Hardening (remaining)

| Issue | Feature | Description |
|-------|---------|-------------|
| [#56](https://github.com/gregwinn/winn-lang/issues/56) | Compiler errors | Better error handling for edge cases |
| [#57](https://github.com/gregwinn/winn-lang/issues/57) | Validators | Extended changeset validators |
| [#100](https://github.com/gregwinn/winn-lang/issues/100) | Transform hardening | Pass ordering tests and invariant docs |
| [#117](https://github.com/gregwinn/winn-lang/issues/117) | Lint config | Configurable lint rules via `.winn-lint.json` |
| [#120](https://github.com/gregwinn/winn-lang/issues/120) | LSP Phase 3 | Completion, find references, formatting integration |
| [#129](https://github.com/gregwinn/winn-lang/issues/129) | Type annotations | Gradual type checking |
| [#130](https://github.com/gregwinn/winn-lang/issues/130) | Test fixtures | Setup/teardown, fixtures, and skip support |
| [#131](https://github.com/gregwinn/winn-lang/issues/131) | Stdlib docs | Complete Changeset, Server, Health, Repo documentation |
| [#132](https://github.com/gregwinn/winn-lang/issues/132) | `winn doctor` | Environment diagnostics command |

### v1.0.0 — The Winn Platform

| Issue | Feature | Description |
|-------|---------|-------------|
| [#32](https://github.com/gregwinn/winn-lang/issues/32) | AI Pipelines | `AI.chat()`, `AI.classify()`, `AI.extract()` as stdlib, Agent DSL, Smart Pipes |
| [#33](https://github.com/gregwinn/winn-lang/issues/33) | Distributed Events | `Event.emit` / `on :event do` across BEAM nodes, zero infrastructure |
| [#34](https://github.com/gregwinn/winn-lang/issues/34) | Background Jobs | `use Winn.Job` with queues, retries, cron, live dashboard |
| [#103](https://github.com/gregwinn/winn-lang/issues/103) | **Reactive events** | Language-level `on`/`emit` pub/sub built on BEAM distribution |
| [#108](https://github.com/gregwinn/winn-lang/issues/108) | **Distributed clustering** | `Winn.connect(:node@host)` — agents, events, and pipelines auto-span nodes |

### Ecosystem

| Issue | Feature | Description |
|-------|---------|-------------|
| [#20](https://github.com/gregwinn/winn-lang/issues/20) | Example projects | Todo API, chat server, GitHub sync worker |
| [#21](https://github.com/gregwinn/winn-lang/issues/21) | Package registry | Hosted Winn-native registry, `winn publish`, search, discovery |
| [#101](https://github.com/gregwinn/winn-lang/issues/101) | Package registry v2 | Dependency resolution, lockfile, `winn search` |

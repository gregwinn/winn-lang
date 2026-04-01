# Winn Roadmap

## Current Status — v0.7.0

537 tests passing. Homebrew install (`brew install gregwinn/winn/winn`). VS Code extension with syntax highlighting and compile-on-save diagnostics.

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

---

## Coming Next

### v0.8.0 — Web Framework

| Issue | Feature | Description |
|-------|---------|-------------|
| [#47](https://github.com/gregwinn/winn-lang/issues/47) | Static files | Serve CSS/JS/images from a directory |
| [#48](https://github.com/gregwinn/winn-lang/issues/48) | CORS | Built-in CORS middleware |
| [#49](https://github.com/gregwinn/winn-lang/issues/49) | Sessions | Cookie and session support |
| [#50](https://github.com/gregwinn/winn-lang/issues/50) | File uploads | Multipart form data parsing |
| [#51](https://github.com/gregwinn/winn-lang/issues/51) | Auth middleware | Bearer token and session auth |
| [#65](https://github.com/gregwinn/winn-lang/issues/65) | Health checks | `/healthz` and `/ready` for Kubernetes |

### v0.9.0 — Developer Tooling

| Issue | Feature | Description |
|-------|---------|-------------|
| [#52](https://github.com/gregwinn/winn-lang/issues/52) | Formatter | `winn fmt` for consistent code style |
| [#53](https://github.com/gregwinn/winn-lang/issues/53) | Linter | `winn lint` for static analysis |
| [#54](https://github.com/gregwinn/winn-lang/issues/54) | Scaffold | Improved `winn new` with test/, config/ |
| [#55](https://github.com/gregwinn/winn-lang/issues/55) | LSP | Language server for IDE integration |

### v0.10.0 — Hardening

| Issue | Feature | Description |
|-------|---------|-------------|
| [#56](https://github.com/gregwinn/winn-lang/issues/56) | Compiler errors | Better error handling for edge cases |
| [#57](https://github.com/gregwinn/winn-lang/issues/57) | Validators | Extended changeset validators |
| [#58](https://github.com/gregwinn/winn-lang/issues/58) | Bounds checking | Safe defaults for runtime functions |

### v1.0.0 — The Winn Platform

| Issue | Feature | Description |
|-------|---------|-------------|
| [#32](https://github.com/gregwinn/winn-lang/issues/32) | AI Pipelines | `AI.chat()`, `AI.classify()`, `AI.extract()` as stdlib, Agent DSL, Smart Pipes |
| [#33](https://github.com/gregwinn/winn-lang/issues/33) | Distributed Events | `Event.emit` / `on :event do` across BEAM nodes, zero infrastructure |
| [#34](https://github.com/gregwinn/winn-lang/issues/34) | Background Jobs | `use Winn.Job` with queues, retries, cron, live dashboard |

### Ecosystem

| Issue | Feature | Description |
|-------|---------|-------------|
| [#20](https://github.com/gregwinn/winn-lang/issues/20) | Example projects | Todo API, chat server, GitHub sync worker |
| [#21](https://github.com/gregwinn/winn-lang/issues/21) | Package registry | `winn publish`, dependency resolution |

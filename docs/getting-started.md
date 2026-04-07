# Getting Started with Winn

This guide walks you through installing Winn, creating your first project, and building a small web service.

---

## 1. Install

### macOS (Homebrew)

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

Requires Erlang/OTP 28+ and rebar3.

### Verify

```sh
winn version
# => winn 0.7.0

winn help
```

You should see:

```
Winn 0.7.0 - a compiled language on the BEAM

Usage:
  winn new <name>         Create a new Winn project
  winn compile            Compile all .winn files (src/ or current dir)
  winn compile <file>     Compile a single .winn file
  winn run <file>         Compile and run a single .winn file
  winn start              Compile project and start (keeps VM alive)
  winn start <module>     Start with a specific module
  winn version            Show version
  winn help               Show this help text
```

### Editor Support

Install the [Winn VS Code extension](https://github.com/gregwinn/language-winn-vscode) for syntax highlighting and diagnostics.

---

## 2. Create a Project

```sh
winn new my_app
cd my_app
```

This creates:

```
my_app/
├── rebar.config           # Erlang build config
├── .gitignore
├── package.json
├── src/
│   ├── my_app.winn        # Your first Winn file
│   ├── models/
│   ├── controllers/
│   └── tasks/
├── test/
├── db/
│   ├── migrations/
│   └── seeds.winn
└── config/
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

## 3. Run Your Program

```sh
winn run src/my_app.winn
```

Output:

```
Hello from MyApp!
```

---

## 4. Compile to BEAM

Compile your `.winn` files to `.beam` bytecode:

```sh
# Compile a single file
winn compile src/my_app.winn

# Compile all .winn files in src/ (or current dir)
winn compile
# => Compiled 1 file(s) to ebin/
```

Compiled `.beam` files are written to `ebin/`.

## 5. Start a Project

For multi-file projects (especially servers), use `winn start`:

```sh
winn start
```

This compiles all `src/*.winn` files, loads dependencies (Cowboy, hackney, etc.), calls `main()`, and **keeps the VM alive** — essential for HTTP servers and GenServers.

You can also specify which module to start:

```sh
winn start my_app
```

---

## 6. Project Structure

A typical Winn project looks like this:

```
my_app/
├── rebar.config               # Dependencies and build config
├── .gitignore
├── package.json
├── src/
│   ├── my_app.winn            # Application entry point
│   ├── models/
│   │   └── user.winn          # User schema
│   ├── controllers/
│   │   └── api_controller.winn  # HTTP routes
│   └── tasks/
│       └── db_seed.winn       # Background tasks
├── test/
├── db/
│   ├── migrations/            # Database migrations
│   └── seeds.winn
├── config/                    # Configuration files
└── ebin/                      # Compiled .beam files (generated)
```

---

## 7. Your First Module

Winn programs are organized into modules. Each module lives in its own `.winn` file.

Create `src/greeter.winn`:

```winn
module Greeter
  def hello(name)
    "Hello, #{name}!"
  end

  def hello(:world)
    "Hello, World!"
  end
end
```

Compile it:

```sh
winn compile src/greeter.winn
```

Use it from another module:

```winn
module MyApp
  def main()
    msg = Greeter.hello("Alice")
    IO.puts(msg)
  end
end
```

---

## 8. Working with Data

### Lists, Maps, and Tuples

```winn
module DataExample
  def main()
    # Lists
    numbers = [1, 2, 3, 4, 5]
    doubled = for n in numbers do n * 2 end
    IO.inspect(doubled)

    # Maps
    user = %{name: "Alice", age: 30}
    IO.puts(user.name)

    # Tuples
    result = {:ok, "success"}
    IO.inspect(result)
  end
end
```

### Pattern Matching

```winn
module Patterns
  def describe({:ok, value})
    "Success: #{value}"
  end

  def describe({:error, reason})
    "Error: #{reason}"
  end

  def main()
    IO.puts(describe({:ok, "done"}))
    IO.puts(describe({:error, "not found"}))
  end
end
```

### Pipes

```winn
module PipeExample
  def main()
    1..10
      |> Enum.filter() do |x| x > 5 end
      |> Enum.map() do |x| x * 100 end
      |> Enum.join(", ")
      |> IO.puts()
  end
end
```

---

## 9. Error Handling

```winn
module SafeMath
  def divide(a, b) when b != 0
    {:ok, a / b}
  end

  def divide(_, 0)
    {:error, "division by zero"}
  end

  def main()
    match divide(10, 3)
      ok result => IO.puts("Result: #{to_string(result)}")
      err msg   => IO.puts("Error: #{msg}")
    end

    # Or use try/rescue for exceptions
    result = try
      risky_operation()
    rescue
      _ => :fallback
    end
  end
end
```

---

## 10. Build a Web Service

Create `src/api.winn`:

```winn
module Api
  use Winn.Router

  def routes()
    [
      {:get, "/", :index},
      {:get, "/health", :health},
      {:get, "/users/:id", :get_user},
      {:post, "/users", :create_user}
    ]
  end

  def middleware()
    [:log_request]
  end

  def log_request(conn, next)
    Logger.info("#{Server.method(conn)} #{Server.path(conn)}")
    next(conn)
  end

  def index(conn)
    Server.json(conn, %{message: "Welcome to MyApp"})
  end

  def health(conn)
    Server.json(conn, %{status: "ok"})
  end

  def get_user(conn)
    id = Server.path_param(conn, "id")
    Server.json(conn, %{id: id, name: "User #{id}"})
  end

  def create_user(conn)
    params = Server.body_params(conn)
    Logger.info("Creating user", params)
    Server.json(conn, params, 201)
  end
end
```

Create `src/my_app.winn` to start the server:

```winn
module MyApp
  def main()
    IO.puts("Starting server on port 4000...")
    Server.start(Api, 4000)
  end
end
```

Start the server:

```sh
winn start
```

Output:

```
Compiled 2 file(s) to ebin/
Starting myapp...
Starting server on port 4000...
```

Test it:

```sh
curl http://localhost:4000/
# => {"message":"Welcome to MyApp"}

curl http://localhost:4000/users/42
# => {"id":"42","name":"User 42"}

curl -X POST http://localhost:4000/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice"}'
# => {"name":"Alice"}
```

---

## 11. Add a Database Schema

Create `src/user.winn`:

```winn
module User
  use Winn.Schema

  schema "users" do
    field :name,  :string
    field :email, :string
    field :age,   :integer
  end
end
```

Use it with changesets and the Repo:

```winn
module UserService
  def create(params)
    data = User.new(%{})
    changeset = Changeset.new(data, params)
    changeset = Changeset.validate_required(changeset, [:name, :email])

    if Changeset.valid(changeset)
      Repo.insert(User, Changeset.apply_changes(changeset))
    else
      {:error, Changeset.errors(changeset)}
    end
  end

  def find(id)
    Repo.get(User, id)
  end

  def all()
    Repo.all(User)
  end
end
```

---

## 12. Environment and Configuration

```winn
module Config
  def setup()
    # Read environment variables
    port = System.get_env("PORT", "4000")
    secret = System.get_env("JWT_SECRET", "dev_secret")

    # Load config
    Config.load(%{
      http: %{port: to_integer(port)},
      auth: %{secret: secret}
    })
  end
end
```

---

## 13. Compile Errors

Winn gives you clear error messages when something goes wrong:

```
-- Syntax Error ----------------------------- src/app.winn --

3 |     x +
4 |   end
  |   ^^^
5 | end
  Unexpected 'end'.
  Hint: Did you close a block too early, or forget an expression?
```

If you're using the VS Code extension, errors show as red squigglies inline.

---

## 14. Testing

Write tests in Winn using `use Winn.Test`:

```winn
module MathTest
  use Winn.Test

  def test_addition()
    assert(1 + 1 == 2)
  end

  def test_greeting()
    result = "Hello, " <> "World"
    assert_equal("Hello, World", result)
  end
end
```

Save as `test/math_test.winn` and run:

```sh
winn test
```

Output:

```
  ✓ mathtest:test_addition
  ✓ mathtest:test_greeting

2 tests, 0 failures (0ms)
```

Test functions must be named `test_*` with zero arguments. Use `assert(expr)` for boolean checks and `assert_equal(expected, actual)` for value comparisons.

---

## 15. Generating Documentation

Generate API docs from your source with `winn docs`:

```sh
winn docs
# => Generated docs for 3 module(s) in doc/api/
```

This creates Markdown files in `doc/api/` with function signatures extracted from `#` doc comments, plus a **Mermaid dependency graph** in `index.md` that renders on GitHub.

---

## 16. Watch Mode

Use `winn watch` for automatic recompilation and hot code reloading during development:

```sh
winn watch --start
```

This starts your app and shows a live terminal dashboard. When you edit a `.winn` file, the module is recompiled and hot-reloaded without restarting the VM.

---

## 17. Code Generators

Scaffold models, migrations, tasks, and routers:

```sh
winn create model User name:string email:string
# => src/models/user.winn

winn create migration CreateUsers name:string email:string
# => db/migrations/TIMESTAMP_create_users.winn

winn create task db:seed
# => src/tasks/db_seed.winn

winn create router Api
# => src/controllers/api_controller.winn  (module ApiController)

winn create scaffold Post title:string body:text
# => src/models/post.winn, src/controllers/post_controller.winn, test/post_test.winn

winn c model User   # shorthand
```

---

## 18. Code Formatting

Format your code for consistent style with `winn fmt`:

```sh
winn fmt                   # format all .winn files
winn fmt src/app.winn      # format a specific file
winn fmt --check           # check formatting without modifying (CI)
```

---

## 19. Linting

Run static analysis to catch common issues:

```sh
winn lint                  # lint all .winn files
winn lint src/app.winn     # lint a specific file
```

The linter checks for unused variables, unused imports/aliases, naming conventions, redundant boolean comparisons, empty function bodies, and more. See [`winn lint`](cli.md#winn-lint) for the full list of rules.

---

## 20. Database Migrations

Manage your database schema with migrations:

```sh
winn migrate              # Run all pending migrations
winn rollback             # Rollback last migration
winn migrate --status     # Show migration status
```

---

## 21. Deployment

Build production releases:

```sh
winn release              # Build a production release
winn release --docker     # Generate a Dockerfile
```

---

## 22. Metrics and Load Testing

Monitor your app with built-in metrics:

```winn
Metrics.enable()
Metrics.increment(:api_calls)
Metrics.set(:active_users, 42)
Metrics.observe(:latency, 12.5)
```

View a live dashboard:

```sh
winn metrics
```

Run load tests:

```sh
winn bench bench/api_bench.winn
```

---

## 23. Packages

Install optional add-on packages with `winn add`:

```sh
winn add redis       # install Redis client
winn add mongodb     # install MongoDB client
winn add amqp        # install RabbitMQ client
winn packages        # list installed
```

Use them in your code:

```winn
Redis.configure(%{url: "redis://localhost:6379"})
Redis.set("key", "value")
{:ok, val} = Redis.get("key")
```

Packages are written in Winn and declared in `package.json`. Anyone can create and share packages.

---

## Next Steps

- [Language Guide](language.md) — full syntax reference
- [Standard Library](stdlib.md) — IO, String, Enum, List, Map, System, UUID, DateTime, Logger, Crypto
- [OTP Integration](otp.md) — GenServer, Supervisor, Application
- [ORM](orm.md) — Schema, Repo, Changeset
- [Modules](modules.md) — HTTP server/client, JWT, WebSockets, Tasks, Config
- [CLI Reference](cli.md) — all CLI commands

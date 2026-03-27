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
winn help
```

You should see:

```
Winn - a compiled language on the BEAM

Usage:
  winn new <name>       Create a new Winn project
  winn compile          Compile all *.winn files in current directory
  winn compile <file>   Compile a single .winn file
  winn run <file>       Compile and run a .winn file
  winn help             Show this help text
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
├── rebar.config       # Erlang build config
├── .gitignore
└── src/
    └── my_app.winn    # Your first Winn file
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

# Compile all .winn files in the current directory
winn compile
```

Compiled `.beam` files are written to `ebin/`. You can run them directly with Erlang:

```sh
erl -pa ebin -noshell -eval 'my_app:main(), halt().'
```

---

## 5. Project Structure

A typical Winn project looks like this:

```
my_app/
├── rebar.config           # Dependencies and build config
├── .gitignore
├── src/
│   ├── my_app.winn        # Application entry point
│   ├── router.winn        # HTTP routes
│   ├── user.winn          # User schema
│   └── auth.winn          # Authentication logic
├── ebin/                  # Compiled .beam files (generated)
└── config/                # Configuration files (optional)
```

---

## 6. Your First Module

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

## 7. Working with Data

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

## 8. Error Handling

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

## 9. Build a Web Service

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

Compile and run:

```sh
winn compile src/api.winn
winn compile src/my_app.winn
erl -pa ebin -pa _build/default/lib/*/ebin -noshell -eval 'my_app:main().'
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

## 10. Add a Database Schema

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

## 11. Environment and Configuration

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

## 12. Compile Errors

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

## Next Steps

- [Language Guide](language.md) — full syntax reference
- [Standard Library](stdlib.md) — IO, String, Enum, List, Map, System, UUID, DateTime, Logger, Crypto
- [OTP Integration](otp.md) — GenServer, Supervisor, Application
- [ORM](orm.md) — Schema, Repo, Changeset
- [Modules](modules.md) — HTTP server/client, JWT, WebSockets, Tasks, Config
- [CLI Reference](cli.md) — all CLI commands

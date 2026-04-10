# OTP Integration

Winn has first-class support for OTP behaviours. The `agent` keyword provides zero-boilerplate stateful actors, and `use` directives give full access to GenServer, Supervisor, Application, and Task.

## Agent

The `agent` keyword creates a stateful actor that compiles to a GenServer under the hood — no `handle_call`, `init`, or boilerplate required.

### Defining an Agent

```winn
agent Counter
  state count = 0

  def increment()
    @count = @count + 1
  end

  def increment(amount)
    @count = @count + amount
  end

  def value()
    @count
  end

  def reset()
    @count = 0
    :ok
  end

  async def log_reset()
    @count = 0
  end
end
```

### Using an Agent

```winn
counter = Counter.start()         # start with default state
Counter.increment(counter)        # synchronous call, returns 1
Counter.increment(counter, 5)     # returns 6
IO.puts(Counter.value(counter))   # prints 6
Counter.log_reset(counter)        # fire-and-forget (async)
```

### Start with Overrides

```winn
counter = Counter.start(%{count: 100})
IO.puts(Counter.value(counter))   # prints 100
```

### Key Concepts

- **`state name = default`** — declare state variables with defaults
- **`@name`** — read state; **`@name = expr`** — write state
- **`def`** — synchronous functions (gen_server:call)
- **`async def`** — fire-and-forget functions (gen_server:cast), always returns `:ok`
- **`start()`** — start with defaults; **`start(%{...})`** — merge overrides
- Each agent instance is an independent BEAM process
- Agents support multi-clause functions with pattern matching and guards

### Agent vs GenServer

Use `agent` when you want clean stateful actors with minimal code. Use `use Winn.GenServer` when you need full control over OTP callbacks, custom `handle_info`, or process linking.

## GenServer

A GenServer is a stateful process that handles synchronous calls and asynchronous casts.

### Defining a GenServer

```winn
module Counter
  use Winn.GenServer

  def init(initial)
    {:ok, initial}
  end

  def handle_call(:get, _from, state)
    {:reply, state, state}
  end

  def handle_cast({:inc, n}, state)
    {:noreply, state + n}
  end

  def handle_cast(:reset, _state)
    {:noreply, 0}
  end

  def handle_info(_msg, state)
    {:noreply, state}
  end

  def terminate(_reason, _state)
    :ok
  end
end
```

`use Winn.GenServer` automatically:
- Adds `-behaviour(gen_server)` to the compiled module
- Generates a `start_link/1` function that registers the process locally

### Starting and Using

```erlang
%% From Erlang / rebar3 shell after compiling
{ok, Pid} = counter:start_link(0).
gen_server:cast(Pid, {inc, 5}).
gen_server:cast(Pid, {inc, 3}).
8 = gen_server:call(Pid, get).
gen_server:stop(Pid).
```

### Callbacks

| Callback | Purpose |
|----------|---------|
| `init(args)` | Initialize state. Return `{:ok, state}`. |
| `handle_call(msg, from, state)` | Handle synchronous request. Return `{:reply, response, state}`. |
| `handle_cast(msg, state)` | Handle async message. Return `{:noreply, state}`. |
| `handle_info(msg, state)` | Handle out-of-band messages. Return `{:noreply, state}`. |
| `terminate(reason, state)` | Cleanup on shutdown. Return `:ok`. |

### Pattern Matching in Callbacks

Multi-clause functions work naturally as GenServer callbacks:

```winn
module Stack
  use Winn.GenServer

  def init(items)
    {:ok, items}
  end

  def handle_call(:pop, _from, [head | tail])
    {:reply, {:ok, head}, tail}
  end

  def handle_call(:pop, _from, [])
    {:reply, :empty, []}
  end

  def handle_cast({:push, item}, state)
    {:noreply, [item | state]}
  end

  def handle_info(_msg, state)
    {:noreply, state}
  end

  def terminate(_reason, _state)
    :ok
  end
end
```

---

## Supervisor

```winn
module MyApp.Supervisor
  use Winn.Supervisor

  def init(_args)
    {:ok, {
      %{strategy: :one_for_one},
      [{Counter, :start_link, [0]}]
    }}
  end
end
```

`use Winn.Supervisor` generates `start_link/1` and adds `-behaviour(supervisor)`.

---

## Application

Define an OTP application entry point with `use Winn.Application`:

```winn
module MyApp
  use Winn.Application

  def start(_type, _args)
    children = [
      {Counter, [0]},
      {MyApp.Repo, []}
    ]
    Supervisor.start_link(children, %{strategy: :one_for_one})
  end
end
```

`use Winn.Application` adds `-behaviour(application)` to the compiled module.

---

## Task (use Winn.Task)

Define CLI-runnable task modules with `use Winn.Task`:

```winn
module Tasks.Db.Migrate
  use Winn.Task

  def run(args)
    IO.puts("Running migrations...")
  end
end
```

`use Winn.Task` adds `-behaviour(winn_task)` to the compiled module.

---

## Test (use Winn.Test)

Define test modules with `use Winn.Test`:

```winn
module UserTest
  use Winn.Test

  def test_create()
    assert(1 + 1 == 2)
  end

  def test_equality()
    assert_equal("hello", "hello")
  end
end
```

`use Winn.Test` adds `-behaviour(winn_test)`. Test functions must be named `test_*`. Run with `winn test`. See [CLI Reference](cli.md#winn-test-file) and [Standard Library](stdlib.md#testing) for details.

---

## Calling OTP Functions

Use `GenServer` and `Supervisor` module calls from Winn:

```winn
GenServer.call(pid, :get)
GenServer.cast(pid, {:inc, 1})
GenServer.start_link(MyModule, args, [])
GenServer.reply(from, response)
```

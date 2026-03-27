# OTP Integration

Winn has first-class support for OTP behaviours via the `use` directive.

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

## Calling OTP Functions

Use `GenServer` and `Supervisor` module calls from Winn:

```winn
GenServer.call(pid, :get)
GenServer.cast(pid, {:inc, 1})
GenServer.start_link(MyModule, args, [])
GenServer.reply(from, response)
```

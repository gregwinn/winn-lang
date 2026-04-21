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

## Pipeline

The `pipeline` keyword builds Broadway-shape supervised dataflows: a single producer feeds a pool of concurrent processors, which can optionally funnel results into a batcher. Each stage is its own gen_server, the whole pipeline lives under one supervisor, and backpressure is driven by the producer's prefetch count.

### Defining a Pipeline

```winn
pipeline FleetDelivery
  producer :amqp,
    source: FleetAmqpProducer,
    queue: "fleet.events",
    prefetch: 50

  processor :default,
    concurrency: 10,
    retry: 3,
    timeout: 5000 do |msg|
    FleetService.process(msg)
  end

  batcher :mongo,
    size: 100,
    timeout: 1000 do |batch|
    MongoClient.bulk_upsert(batch)
  end
end
```

### Using a Pipeline

```winn
FleetDelivery.start_link()   # starts the supervisor tree
FleetDelivery.stats()        # %{processed: N, errors: N, retries: N, ...}
FleetDelivery.stop()         # graceful drain
```

### The Producer Behaviour

Pipelines don't ship with any built-in source — you write a module that implements a four-function callback set. Keep the module simple; the pipeline runtime handles supervision, metrics, and backpressure around it.

| Callback | Purpose | Return |
|---|---|---|
| `init(opts)` | Open the upstream source (AMQP channel, DB cursor, file handle). | `{:ok, state}` or `{:error, reason}` |
| `pull(state, demand)` | Fetch up to `demand` messages. Return fewer (or `[]`) if you want the runtime to retry after a short backoff. | `{:ok, messages, state}` or `{:error, reason, state}` |
| `ack(state, message, outcome)` | Acknowledge a completed message upstream. `outcome` is `:ack` or `{:nack, reason}`. | new `state` |
| `terminate(state, reason)` | Close the source cleanly. | `:ok` |

All `opts` besides the framework keys (`source`, `prefetch`) pass through to `init/1` as a map.

### Stage Options

- `producer`:
  - `source:` — **required**. The module implementing the producer behaviour.
  - `prefetch:` — max messages in flight across the worker pool (default `10`).
  - any other `key: value` pair is forwarded to `init/1`.
- `processor`:
  - `concurrency:` — number of parallel workers (default `1`).
  - `retry:` — retry count on handler failure (default `0`, no retry).
  - `timeout:` — per-message timeout in milliseconds (default `infinity`).
- `batcher` (optional stage):
  - `size:` — flush threshold (default `100`).
  - `timeout:` — idle flush in milliseconds (default `1000`).

### Supervision & Shutdown

A pipeline `FleetDelivery` compiles to a supervisor whose tree looks like:

```
fleetdelivery (one_for_all)
├── fleetdelivery_batcher      (optional)
├── fleetdelivery_worker_1
├── ...
├── fleetdelivery_worker_N
└── fleetdelivery_producer
```

On `stop/0` or SIGTERM the supervisor terminates children in reverse order — the producer stops pulling first, workers finish in-flight messages, and the batcher flushes any buffered items before exiting. Pending casts are drained from the batcher's mailbox before the final flush, so nothing sitting between stages gets lost.

### Metrics

The pipeline emits counters and a gauge through the `Metrics` module. Keys are namespaced by the pipeline's module name:

- `<pipeline>.processed`
- `<pipeline>.errors`
- `<pipeline>.retries`
- `<pipeline>.batch_flushes`
- `<pipeline>.in_flight` (gauge)

### Pipeline vs Raw GenServer + Task

Reach for `pipeline` when you need Broadway semantics: bounded concurrency, prefetch backpressure, per-stage supervision, and clean shutdown — without hand-rolling a worker pool and drain protocol. Drop down to `use Winn.GenServer` + `Task.async_stream` when you need a push-based interface, multi-stage dispatch, or topologies the Broadway shape doesn't cover.

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

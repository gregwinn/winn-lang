# Deploying Winn to Production

This guide covers what you need to run a Winn service on Kubernetes: sizing the BEAM against container limits, shipping structured logs, exposing Prometheus metrics, handling SIGTERM cleanly, and the manifests that tie it all together.

Everything here is grounded in what ships with Winn today — `Logger`, `Metrics`, `Health`, and the OTP supervision tree. Where something needs a small glue module (like a Prometheus `/metrics` handler), the code is in this guide.

---

## 1. Resource sizing

### CPU and schedulers

The BEAM starts one scheduler per detected core. Under Kubernetes, "detected" means `nproc` inside the container, which is the *host* CPU count — not your CPU limit. Running with the default can trash performance: 64 schedulers fighting over 1 CPU.

Pin schedulers to match your limit. Put it in the `ERL_FLAGS` env var so the BEAM picks it up at boot.

```yaml
env:
  - name: ERL_FLAGS
    # +S 2:2 — 2 schedulers, 2 online. Match your CPU limit.
    # +sbwt none — disable scheduler busy-wait; huge win under low CPU limits.
    # +sbwtdcpu none +sbwtdio none — same, for dirty CPU/IO schedulers.
    value: "+S 2:2 +sbwt none +sbwtdcpu none +sbwtdio none"
```

Rules of thumb:

| Service type | CPU request | CPU limit | `+S` flag |
|---|---|---|---|
| Low-traffic HTTP API | 100m | 500m | `+S 1:1` |
| Normal HTTP API | 500m | 2000m | `+S 2:2` |
| Queue consumer (high CPU) | 1000m | 4000m | `+S 4:4` |
| Background worker (low CPU) | 100m | 1000m | `+S 1:1` |

Always set CPU **requests** equal to what `+S` implies — the BEAM will saturate its schedulers even if other pods want the CPU. Setting limits well above requests lets you burst during spikes.

### Memory

The BEAM's default process heap is small (233 words). It grows as needed and shrinks on GC. Memory pressure comes from: process count, large binaries (ref-counted), ETS tables, and message queue backlogs.

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "256Mi"
  limits:
    cpu: "2000m"
    memory: "512Mi"
```

Starting points by workload:

| Workload | Request | Limit |
|---|---|---|
| Small HTTP API (< 100 rps) | 128Mi | 256Mi |
| Normal HTTP API | 256Mi | 512Mi |
| Queue consumer with batching | 512Mi | 1Gi |
| Anything using `winn-mongodb` or large JSON payloads | 512Mi | 1Gi |

Watch `beam_memory_total_bytes` in Grafana for a week, then size limits at p99 + 50% headroom. Don't set the limit too tight — the OOM killer gives no warning, and the BEAM can't flush its crash dump before being terminated.

### Atoms and processes

The BEAM has hard ceilings: ~1M atoms and ~262k processes by default. Hit either and the VM dies. Bump them if you're creating dynamic atoms from user input (don't — but sometimes deps do) or spawning many short-lived processes:

```yaml
env:
  - name: ERL_FLAGS
    value: "+S 2:2 +t 5000000 +P 1000000 +sbwt none"
    # +t 5M atoms, +P 1M processes
```

---

## 2. Structured logging

`Logger` writes one JSON object per line to stderr. This format is native input for Loki/Promtail, Datadog, and most log routers.

```winn
Logger.info("request handled", %{
  method: "POST",
  path: "/users",
  status: 201,
  duration_ms: 42,
  user_id: user.id
})
```

Produces:

```json
{"level":"info","msg":"request handled","ts":"2026-04-20T15:04:05Z","method":"POST","path":"/users","status":201,"duration_ms":42,"user_id":42}
```

### Log levels

- `Logger.info/1`, `Logger.info/2` — normal traffic
- `Logger.warn/1`, `Logger.warn/2` — recoverable problems
- `Logger.error/1`, `Logger.error/2` — failures, exceptions
- `Logger.debug/1`, `Logger.debug/2` — development only

All four exist in single-arg (message-only) and two-arg (message + metadata map) forms.

### Promtail / Loki

```yaml
# promtail-config.yaml
scrape_configs:
  - job_name: winn
    kubernetes_sd_configs:
      - role: pod
    pipeline_stages:
      - cri: {}
      - json:
          expressions:
            level: level
            ts: ts
            msg: msg
      - labels:
          level:
      - timestamp:
          source: ts
          format: RFC3339
```

Label on `level` only — labelling on `msg` or user IDs creates cardinality explosions that will cripple Loki.

### Datadog

Datadog Agent auto-parses JSON if you set the log source correctly:

```yaml
annotations:
  ad.datadoghq.com/<container-name>.logs: |
    [{"source": "winn", "service": "<service-name>"}]
```

Add a processor to remap `msg` → `message` and `ts` → `timestamp` in Datadog's pipeline UI.

### What not to log

- Secrets, tokens, full request bodies with PII.
- Full stack traces at `info` — use `error` with a structured `reason` field.
- Per-request log lines at extreme fan-out (> 1k rps) — sample or aggregate.

---

## 3. Prometheus metrics

Winn's `Metrics` module (ETS-backed counters/gauges/histograms, plus HTTP and BEAM stats) is the source. There's no built-in `/metrics` handler, so you expose it via a small route on your existing `Server`.

### Enable metrics on startup

```winn
module MyApp
  def main()
    Metrics.enable()            # creates the ETS tables
    Server.start(MyApp.Router, 4000)
  end
end
```

### The `/metrics` endpoint

Prometheus label values must be wrapped in `"`, which Winn's current string literals don't escape cleanly. Drop this small Erlang helper next to your Winn sources — rebar3 picks up `.erl` files automatically, and a Winn handler can delegate to it. Name it to match what Winn's module-name lowercasing produces (`MetricsPrometheus` → `metricsprometheus`):

```erlang
%% apps/<your_app>/src/metricsprometheus.erl
-module(metricsprometheus).
-export([render/0]).

render() ->
    Snap = winn_metrics:snapshot(),
    Http = winn_metrics:http_snapshot(),
    Beam = winn_metrics:beam_stats(),
    Lines =
        counter_lines(maps:get(counters, Snap, #{}))
        ++ gauge_lines(maps:get(gauges, Snap, #{}))
        ++ histogram_lines(maps:get(histograms, Snap, #{}))
        ++ http_lines(Http)
        ++ beam_lines(Beam),
    iolist_to_binary([lists:join($\n, Lines), $\n]).

counter_lines(M) ->
    maps:fold(fun(K, V, Acc) ->
        N = to_bin(K),
        Acc ++ [<<"# TYPE ", N/binary, " counter">>,
                <<N/binary, " ", (to_bin(V))/binary>>]
    end, [], M).

gauge_lines(M) ->
    maps:fold(fun(K, V, Acc) ->
        N = to_bin(K),
        Acc ++ [<<"# TYPE ", N/binary, " gauge">>,
                <<N/binary, " ", (to_bin(V))/binary>>]
    end, [], M).

histogram_lines(M) ->
    maps:fold(fun(K, Summary, Acc) ->
        N = to_bin(K),
        P50 = to_bin(maps:get(p50, Summary, 0)),
        P95 = to_bin(maps:get(p95, Summary, 0)),
        P99 = to_bin(maps:get(p99, Summary, 0)),
        Cnt = to_bin(maps:get(count, Summary, 0)),
        Acc ++ [
            <<"# TYPE ", N/binary, " summary">>,
            <<N/binary, "{quantile=\"0.5\"} ",  P50/binary>>,
            <<N/binary, "{quantile=\"0.95\"} ", P95/binary>>,
            <<N/binary, "{quantile=\"0.99\"} ", P99/binary>>,
            <<N/binary, "_count ", Cnt/binary>>
        ]
    end, [], M).

http_lines(M) ->
    maps:fold(fun(Key, Stats, Acc) ->
        Label = <<"endpoint=\"", Key/binary, "\"">>,
        Acc ++ [
            <<"http_requests_total{", Label/binary, "} ",
              (to_bin(maps:get(count, Stats)))/binary>>,
            <<"http_errors_total{",   Label/binary, "} ",
              (to_bin(maps:get(errors, Stats)))/binary>>,
            <<"http_request_duration_ms{", Label/binary, ",quantile=\"0.95\"} ",
              (to_bin(maps:get(p95_ms, Stats)))/binary>>
        ]
    end, [], M).

beam_lines(B) ->
    [
        <<"# TYPE beam_process_count gauge">>,
        <<"beam_process_count ",          (to_bin(maps:get(process_count, B)))/binary>>,
        <<"beam_memory_total_bytes ",     (to_bin(maps:get(memory_total, B)))/binary>>,
        <<"beam_memory_processes_bytes ", (to_bin(maps:get(memory_processes, B)))/binary>>,
        <<"beam_memory_ets_bytes ",       (to_bin(maps:get(memory_ets, B)))/binary>>,
        <<"beam_uptime_ms ",              (to_bin(maps:get(uptime_ms, B)))/binary>>
    ].

to_bin(V) when is_binary(V) -> V;
to_bin(V) when is_atom(V)   -> atom_to_binary(V, utf8);
to_bin(V) when is_integer(V) -> integer_to_binary(V);
to_bin(V) when is_float(V)   -> float_to_binary(V, [{decimals, 3}, compact]).
```

The Winn handler is a one-liner that asks the helper for the body and returns it as plain text (Prometheus scrapes `text/plain` just fine):

```winn
module MetricsEndpoint
  def render(conn)
    body = MetricsPrometheus.render()
    Server.text(conn, body)
  end
end
```


Then wire it into your router. Winn routes dispatch to functions in the Router module itself, so expose a thin proxy for each external handler:

```winn
module MyApp.Router
  use Winn.Router

  def routes()
    [
      {:get, "/metrics", :metrics},
      {:get, "/livez",   :livez},
      {:get, "/readyz",  :readyz},
      # ... your app routes
    ]
  end

  def metrics(conn)
    MetricsEndpoint.render(conn)
  end

  def livez(conn)
    Health.liveness(conn)
  end

  def readyz(conn)
    Health.readiness(conn, [
      Health.check(:database, fn() => Repo.execute("SELECT 1") end)
    ])
  end
end
```

### Label discipline

- Prefer a small number of **stable** labels: `method`, `endpoint`, `status_class` (2xx/4xx/5xx).
- **Never** put user IDs, trace IDs, full URLs (with path params), or timestamps in labels. Each unique combination creates a new time series.
- For pipelines (#104), Winn already namespaces metrics as `<pipeline>.processed`, `<pipeline>.errors`, etc. Emit them as separate metrics, not as labels.

### ServiceMonitor (Prometheus Operator)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
  labels:
    release: prometheus        # must match your Prometheus instance selector
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
      scrapeTimeout: 10s
```

---

## 4. Graceful shutdown

### How it works

When Kubernetes sends SIGTERM to PID 1 in your container, the BEAM's default signal handler runs `init:stop/0`, which:

1. Stops each running OTP application in reverse-start order.
2. For each application, terminates its supervision tree top-down.
3. Each supervisor terminates its children in **reverse registration order**, waiting up to each child's `shutdown` timeout.
4. Each gen_server's `terminate/2` callback runs (if it has `trap_exit`; see the OTP section in `docs/otp.md`).
5. The VM exits.

This is what you want. **Do not** add custom SIGTERM traps — you'll fight the OTP machinery.

The key thing you control is:

- **Child spec `shutdown` values** — how long each gen_server has to drain.
- **`terminate/2` implementations** — the actual drain logic.
- **Ordering inside your supervisor** — workers that need to finish last go *first* in the child list (so they terminate last).

### The health-probe flip

The gap between SIGTERM and the container actually exiting is where in-flight requests get dropped if the Service keeps routing to you. Pattern to close it: flip readiness to down *before* the shutdown starts, so kube-proxy removes you from the endpoint slice.

Two options, simplest first:

**Option A: rely on `preStop` + probe timing.** Kubernetes runs `preStop`, *then* sends SIGTERM. Put a sleep in `preStop` longer than `readinessProbe.periodSeconds + failureThreshold` so the endpoint is removed before the app starts draining.

```yaml
lifecycle:
  preStop:
    exec:
      command: ["sleep", "15"]
readinessProbe:
  httpGet:
    path: /readyz
    port: 4000
  periodSeconds: 3
  failureThreshold: 2   # 2 × 3s = 6s to flip, comfortably under the 15s sleep
terminationGracePeriodSeconds: 60
```

This works without any code changes and is enough for 90% of services.

**Option B: app-level ready flag.** If your service has long-running operations that must drain cleanly, add a `ready` flag your `/readyz` consults, and flip it from a `preStop` hook that POSTs to a local `/drain` endpoint:

1. Keep the flag in a named `agent` (e.g. `AppState`) started at boot and registered so your handlers can look it up (`Process.whereis/1` or an ETS lookup your app wraps).
2. In `/readyz`, include an extra `Health.check/2` that raises when the flag is off — `Health.readiness/2` turns a failed check into a `503`.
3. Add a `/drain` route that flips the flag and returns `200`. Make it loopback-only (bind to `127.0.0.1` or check the remote IP) so it can't be triggered from outside the pod.

Then:

```yaml
lifecycle:
  preStop:
    exec:
      command:
        - sh
        - -c
        - 'wget -q -O- --post-data="" http://127.0.0.1:4000/drain; sleep 20'
terminationGracePeriodSeconds: 60
```

Only reach for option B if you need it — option A is enough for almost every service.

### Long-running work at shutdown

Anything that takes more than a second to drain (connection pool, pipeline batcher, background worker) needs its child spec `shutdown` tuned so the supervisor actually waits for it:

```winn
# In your supervisor init
{:ok, {
  %{strategy: :one_for_all, intensity: 3, period: 10},
  [
    #{id: :db_pool,   start: {Repo, :start_link, []},
      shutdown: 5000, type: :worker},
    #{id: :pipeline,  start: {FleetDelivery, :start_link, []},
      shutdown: 30000, type: :supervisor},   # give it 30s to drain
    #{id: :http,      start: {MyApp.Server, :start_link, []},
      shutdown: 10000, type: :worker}
  ]
}}
```

`terminationGracePeriodSeconds` on the pod must be longer than the sum of your shutdown timeouts, or Kubernetes SIGKILLs you mid-drain.

---

## 5. Kubernetes manifest template

Drop-in deployment + service + ingress. Replace `myapp` and `4000` with your service.

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      # Run as non-root (matches the Dockerfile below).
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      terminationGracePeriodSeconds: 60
      containers:
        - name: myapp
          image: ghcr.io/you/myapp:1.2.3  # pin by tag or digest, never :latest
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 4000
          env:
            - name: ERL_FLAGS
              value: "+S 2:2 +sbwt none +sbwtdcpu none +sbwtdio none"
            - name: MIX_ENV
              value: "prod"
            # Pull secrets from the 1Password Operator if you use it.
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: myapp-secrets
                  key: database_url
          resources:
            requests:
              cpu: "500m"
              memory: "256Mi"
            limits:
              cpu: "2000m"
              memory: "512Mi"
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          livenessProbe:
            httpGet:
              path: /livez
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            periodSeconds: 3
            timeoutSeconds: 2
            failureThreshold: 2
          lifecycle:
            preStop:
              exec:
                command: ["sleep", "15"]
          volumeMounts:
            # readOnlyRootFilesystem requires writable paths for anything that writes
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  selector:
    app: myapp
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts: [myapp.example.com]
      secretName: myapp-tls
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

### 1Password Operator

If you're using GitOps with the 1Password Kubernetes Operator, replace the `Secret` reference with a `OnePasswordItem`:

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: myapp-secrets
spec:
  itemPath: "vaults/Production/items/myapp"
```

The operator reconciles this into a regular `Secret` the Deployment can consume. Add these annotations to the Deployment if you want automatic rolling restart on secret change:

```yaml
metadata:
  annotations:
    operator.1password.io/auto-restart: "true"
```

---

## 6. Dockerfile

Multi-stage build. Compiles with rebar3, produces a small runtime image with a non-root user and no build tools.

```dockerfile
# syntax=docker/dockerfile:1.7
ARG ERLANG_VERSION=27.2
ARG DEBIAN_VERSION=bookworm-slim

# ── Build stage ──────────────────────────────────────────────────────────
FROM erlang:${ERLANG_VERSION} AS build

WORKDIR /app

# Copy manifest files first for better layer caching.
COPY rebar.config rebar.lock ./
RUN rebar3 deps

# Now copy source and compile.
COPY apps ./apps
COPY src ./src
COPY config ./config
RUN rebar3 as prod release

# ── Runtime stage ────────────────────────────────────────────────────────
FROM debian:${DEBIAN_VERSION}

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates libssl3 libncurses6 \
 && rm -rf /var/lib/apt/lists/*

# Create a non-root user; match the Deployment's securityContext UID.
RUN groupadd --gid 1000 app \
 && useradd --uid 1000 --gid app --create-home --shell /bin/bash app

WORKDIR /app
COPY --from=build --chown=app:app /app/_build/prod/rel/myapp ./

USER app

EXPOSE 4000

# Run via the release script so the BEAM picks up vm.args / sys.config.
CMD ["bin/myapp", "foreground"]
```

Build and push:

```sh
docker build -t ghcr.io/you/myapp:$(git rev-parse --short HEAD) .
docker push ghcr.io/you/myapp:$(git rev-parse --short HEAD)
```

Pinning tips:

- Pin the Erlang version (`erlang:27.2`, not `erlang:latest`).
- Pin Debian (`bookworm-slim`, not `latest`).
- Tag images by commit SHA, not `:latest` — Kubernetes won't redeploy if the tag doesn't change.

---

## 7. Pre-flight checklist

Before you merge the manifest:

- [ ] `ERL_FLAGS` matches CPU limits (`+S N:N`).
- [ ] `terminationGracePeriodSeconds` ≥ sum of supervisor `shutdown` values + `preStop` sleep.
- [ ] `readinessProbe.failureThreshold × periodSeconds` < `preStop` sleep.
- [ ] `Metrics.enable()` is called in `main()`.
- [ ] `/livez` and `/readyz` are routed and return 200 / 503 as expected.
- [ ] `Logger` is used for structured logs; no `IO.puts` for production output.
- [ ] Memory limits set from observed p99 + 50%, not guessed.
- [ ] Image pinned by SHA or immutable tag.
- [ ] Non-root `securityContext` + `readOnlyRootFilesystem` enabled.
- [ ] Secrets come from 1Password Operator / Vault / sealed-secrets — never baked into the image or committed.

---

## Related docs

- [OTP Integration](otp.md) — supervisor trees, agents, `pipeline` keyword
- [Standard Library](stdlib.md) — `Logger`, `Metrics`, `Health` reference
- [CLI Reference](cli.md) — `winn start`, `winn metrics`

%% winn_bench.erl
%% Built-in load testing: spawn concurrent workers, collect latency stats.

-module(winn_bench).
-export([run/3, run_benchmarks/1, format_results/1, percentile/3]).

%% ── Public API ───────────────────────────────────────────────────────────────

%% Run a single benchmark.
%% Fun/0 is called repeatedly by each worker for Duration seconds.
%% Returns results map with count, avg, percentiles, errors.
-spec run(atom(), map(), fun(() -> term())) -> map().
run(Name, Opts, Fun) ->
    Concurrency = maps:get(concurrent, Opts, 10),
    Duration = maps:get(duration, Opts, 10),

    io:format("~n  ~ts (~B concurrent, ~Bs)~n", [atom_to_list(Name), Concurrency, Duration]),
    io:format("  ~ts~n", [lists:duplicate(40, $\x{2500})]),

    Parent = self(),
    Deadline = erlang:monotonic_time(millisecond) + (Duration * 1000),

    %% Spawn workers
    Workers = [spawn_link(fun() ->
        worker_loop(Fun, Deadline, Parent, [])
    end) || _ <- lists:seq(1, Concurrency)],

    %% Collect results from all workers
    AllResults = collect_results(length(Workers), []),

    %% Aggregate
    Results = aggregate(Name, AllResults, Duration),
    print_results(Results),
    Results.

%% Run benchmarks from a compiled module that exports __bench__/0.
run_benchmarks(Module) ->
    Benchmarks = Module:'__bench__'(),
    io:format("  Winn Bench — ~B benchmark(s)~n", [length(Benchmarks)]),
    lists:map(fun({Name, Opts, Fun}) ->
        run(Name, Opts, Fun)
    end, Benchmarks).

%% ── Worker ──────────────────────────────────────────────────────────────────

worker_loop(Fun, Deadline, Parent, Acc) ->
    Now = erlang:monotonic_time(millisecond),
    case Now >= Deadline of
        true ->
            Parent ! {bench_result, self(), Acc};
        false ->
            Start = erlang:monotonic_time(microsecond),
            Status = try
                Fun(),
                ok
            catch
                _:_ -> error
            end,
            Elapsed = erlang:monotonic_time(microsecond) - Start,
            LatencyMs = Elapsed / 1000,
            worker_loop(Fun, Deadline, Parent, [{LatencyMs, Status} | Acc])
    end.

collect_results(0, Acc) -> lists:flatten(Acc);
collect_results(N, Acc) ->
    receive
        {bench_result, _Pid, Results} ->
            collect_results(N - 1, [Results | Acc])
    after 30000 ->
        lists:flatten(Acc)
    end.

%% ── Aggregation ─────────────────────────────────────────────────────────────

aggregate(Name, Results, Duration) ->
    Latencies = [L || {L, _} <- Results],
    Errors = length([S || {_, S} <- Results, S =:= error]),
    Total = length(Results),
    Sorted = lists:sort(Latencies),
    Len = length(Sorted),

    #{name => Name,
      total => Total,
      rps => case Duration of 0 -> 0; _ -> Total div Duration end,
      errors => Errors,
      error_rate => case Total of 0 -> 0.0; _ -> Errors / Total * 100 end,
      avg => case Len of 0 -> 0; _ -> round(lists:sum(Sorted) / Len) end,
      min => case Sorted of [] -> 0; _ -> round(hd(Sorted)) end,
      max => case Sorted of [] -> 0; _ -> round(lists:last(Sorted)) end,
      p50 => percentile(Sorted, Len, 50),
      p95 => percentile(Sorted, Len, 95),
      p99 => percentile(Sorted, Len, 99)}.

%% ── Display ─────────────────────────────────────────────────────────────────

print_results(R) ->
    #{name := _Name, total := Total, rps := Rps,
      avg := Avg, p50 := P50, p95 := P95, p99 := P99,
      min := Min, max := Max, errors := Errors, error_rate := ErrRate} = R,
    io:format("  Requests:     ~B     (~B/s)~n", [Total, Rps]),
    io:format("  Avg latency:  ~Bms~n", [Avg]),
    io:format("  P50:          ~Bms~n", [P50]),
    io:format("  P95:          ~Bms~n", [P95]),
    io:format("  P99:          ~Bms~n", [P99]),
    io:format("  Min/Max:      ~Bms / ~Bms~n", [Min, Max]),
    io:format("  Errors:       ~B         (~.1f%)~n", [Errors, ErrRate]).

format_results(R) ->
    #{name := Name, total := Total, rps := Rps,
      avg := Avg, p50 := P50, p95 := P95, p99 := P99,
      errors := Errors} = R,
    io_lib:format("~s: ~B reqs (~B/s) avg=~Bms p50=~Bms p95=~Bms p99=~Bms errs=~B",
        [Name, Total, Rps, Avg, P50, P95, P99, Errors]).

%% ── Helpers ─────────────────────────────────────────────────────────────────

percentile(_, 0, _) -> 0;
percentile(Sorted, Len, P) ->
    Index = max(1, min(Len, round(P / 100 * Len))),
    round(lists:nth(Index, Sorted)).

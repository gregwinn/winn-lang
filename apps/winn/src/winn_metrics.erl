%% winn_metrics.erl
%% Built-in metrics collection: counters, gauges, histograms.
%% ETS-backed for zero-overhead concurrent reads.

-module(winn_metrics).
-export([enable/0, increment/1, increment/2, set/2,
         observe/2, time/2,
         get/1, snapshot/0, reset/1, reset_all/0,
         http_snapshot/0, record_http/4,
         beam_stats/0, prometheus/0]).

-define(COUNTERS, winn_metrics_counters).
-define(GAUGES, winn_metrics_gauges).
-define(HISTOGRAMS, winn_metrics_histograms).
-define(HTTP, winn_metrics_http).
-define(HISTOGRAM_SIZE, 1000).

%% ── Initialization ──────────────────────────────────────────────────────────

enable() ->
    ensure_table(?COUNTERS, set),
    ensure_table(?GAUGES, set),
    ensure_table(?HISTOGRAMS, set),
    ensure_table(?HTTP, set),
    ok.

ensure_table(Name, Type) ->
    case ets:whereis(Name) of
        undefined ->
            ets:new(Name, [named_table, public, Type, {read_concurrency, true},
                           {write_concurrency, true}]),
            ok;
        _ -> ok
    end.

%% ── Counters ────────────────────────────────────────────────────────────────

increment(Name) ->
    increment(Name, 1).

increment(Name, Amount) when is_atom(Name), is_integer(Amount) ->
    ensure_table(?COUNTERS, set),
    try
        ets:update_counter(?COUNTERS, Name, {2, Amount})
    catch
        error:badarg ->
            ets:insert(?COUNTERS, {Name, Amount})
    end,
    ok.

%% ── Gauges ──────────────────────────────────────────────────────────────────

set(Name, Value) when is_atom(Name) ->
    ensure_table(?GAUGES, set),
    ets:insert(?GAUGES, {Name, Value}),
    ok.

%% ── Histograms ──────────────────────────────────────────────────────────────

observe(Name, Value) when is_atom(Name), is_number(Value) ->
    ensure_table(?HISTOGRAMS, set),
    case ets:lookup(?HISTOGRAMS, Name) of
        [{Name, Values}] when length(Values) >= ?HISTOGRAM_SIZE ->
            %% Circular buffer: drop oldest, add newest
            ets:insert(?HISTOGRAMS, {Name, tl(Values) ++ [Value]});
        [{Name, Values}] ->
            ets:insert(?HISTOGRAMS, {Name, Values ++ [Value]});
        [] ->
            ets:insert(?HISTOGRAMS, {Name, [Value]})
    end,
    ok.

%% ── Timer (convenience) ────────────────────────────────────────────────────

time(Name, Fun) when is_atom(Name), is_function(Fun, 0) ->
    Start = erlang:monotonic_time(microsecond),
    Result = Fun(),
    Elapsed = (erlang:monotonic_time(microsecond) - Start) / 1000, %% ms
    observe(Name, Elapsed),
    Result.

%% ── HTTP Metrics ────────────────────────────────────────────────────────────
%% Called by middleware to record request metrics.

record_http(Method, Path, StatusCode, LatencyMs) ->
    ensure_table(?HTTP, set),
    Key = iolist_to_binary([Method, " ", Path]),
    case ets:lookup(?HTTP, Key) of
        [{Key, Data}] ->
            Count = maps:get(count, Data, 0) + 1,
            Errors = case StatusCode >= 500 of
                true  -> maps:get(errors, Data, 0) + 1;
                false -> maps:get(errors, Data, 0)
            end,
            TotalMs = maps:get(total_ms, Data, 0) + LatencyMs,
            Latencies = maps:get(latencies, Data, []),
            NewLatencies = case length(Latencies) >= ?HISTOGRAM_SIZE of
                true  -> tl(Latencies) ++ [LatencyMs];
                false -> Latencies ++ [LatencyMs]
            end,
            ets:insert(?HTTP, {Key, #{count => Count, errors => Errors,
                                      total_ms => TotalMs, latencies => NewLatencies}});
        [] ->
            ets:insert(?HTTP, {Key, #{count => 1, errors => 0,
                                      total_ms => LatencyMs, latencies => [LatencyMs]}})
    end,
    ok.

http_snapshot() ->
    ensure_table(?HTTP, set),
    Entries = ets:tab2list(?HTTP),
    maps:from_list([{Key, summarize_http(Data)} || {Key, Data} <- Entries]).

summarize_http(#{count := Count, errors := Errors, total_ms := TotalMs, latencies := Latencies}) ->
    Sorted = lists:sort(Latencies),
    Len = length(Sorted),
    #{count => Count,
      errors => Errors,
      avg_ms => case Count of 0 -> 0; _ -> round(TotalMs / Count) end,
      p50_ms => percentile(Sorted, Len, 50),
      p95_ms => percentile(Sorted, Len, 95),
      p99_ms => percentile(Sorted, Len, 99)}.

%% ── Reading Metrics ─────────────────────────────────────────────────────────

get(Name) when is_atom(Name) ->
    case ets:whereis(?COUNTERS) of
        undefined -> 0;
        _ ->
            case ets:lookup(?COUNTERS, Name) of
                [{_, V}] -> V;
                [] ->
                    case ets:whereis(?GAUGES) of
                        undefined -> 0;
                        _ ->
                            case ets:lookup(?GAUGES, Name) of
                                [{_, V}] -> V;
                                [] -> 0
                            end
                    end
            end
    end.

snapshot() ->
    Counters = case ets:whereis(?COUNTERS) of
        undefined -> #{};
        _ -> maps:from_list(ets:tab2list(?COUNTERS))
    end,
    Gauges = case ets:whereis(?GAUGES) of
        undefined -> #{};
        _ -> maps:from_list(ets:tab2list(?GAUGES))
    end,
    Histograms = case ets:whereis(?HISTOGRAMS) of
        undefined -> #{};
        _ -> maps:from_list([{K, summarize_histogram(V)} || {K, V} <- ets:tab2list(?HISTOGRAMS)])
    end,
    #{counters => Counters, gauges => Gauges, histograms => Histograms}.

summarize_histogram(Values) ->
    Sorted = lists:sort(Values),
    Len = length(Sorted),
    #{count => Len,
      avg => case Len of 0 -> 0; _ -> lists:sum(Sorted) / Len end,
      min => case Sorted of [] -> 0; _ -> hd(Sorted) end,
      max => case Sorted of [] -> 0; _ -> lists:last(Sorted) end,
      p50 => percentile(Sorted, Len, 50),
      p95 => percentile(Sorted, Len, 95),
      p99 => percentile(Sorted, Len, 99)}.

%% ── Reset ───────────────────────────────────────────────────────────────────

reset(Name) ->
    lists:foreach(fun(Tab) ->
        case ets:whereis(Tab) of
            undefined -> ok;
            _ -> ets:delete(Tab, Name)
        end
    end, [?COUNTERS, ?GAUGES, ?HISTOGRAMS, ?HTTP]).

reset_all() ->
    lists:foreach(fun(Tab) ->
        case ets:whereis(Tab) of
            undefined -> ok;
            _ -> ets:delete_all_objects(Tab)
        end
    end, [?COUNTERS, ?GAUGES, ?HISTOGRAMS, ?HTTP]).

%% ── BEAM VM Stats ───────────────────────────────────────────────────────────

beam_stats() ->
    #{process_count => erlang:system_info(process_count),
      process_limit => erlang:system_info(process_limit),
      memory_total => erlang:memory(total),
      memory_processes => erlang:memory(processes),
      memory_binary => erlang:memory(binary),
      memory_ets => erlang:memory(ets),
      atom_count => erlang:system_info(atom_count),
      atom_limit => erlang:system_info(atom_limit),
      scheduler_count => erlang:system_info(schedulers),
      uptime_ms => erlang:monotonic_time(millisecond) - erlang:system_info(start_time)}.

%% ── Prometheus Exposition Format ────────────────────────────────────────────
%% Renders the current metrics state as a Prometheus v0.0.4 text exposition
%% binary suitable for serving from a /metrics endpoint.

prometheus() ->
    Snap = snapshot(),
    Http = http_snapshot(),
    Beam = beam_stats(),
    Lines =
        counter_lines(maps:get(counters, Snap, #{}))
        ++ gauge_lines(maps:get(gauges, Snap, #{}))
        ++ histogram_lines(maps:get(histograms, Snap, #{}))
        ++ http_lines(Http)
        ++ beam_lines(Beam),
    iolist_to_binary([lists:join($\n, Lines), $\n]).

counter_lines(M) ->
    maps:fold(fun(K, V, Acc) ->
        N = prom_bin(K),
        Acc ++ [<<"# TYPE ", N/binary, " counter">>,
                <<N/binary, " ", (prom_bin(V))/binary>>]
    end, [], M).

gauge_lines(M) ->
    maps:fold(fun(K, V, Acc) ->
        N = prom_bin(K),
        Acc ++ [<<"# TYPE ", N/binary, " gauge">>,
                <<N/binary, " ", (prom_bin(V))/binary>>]
    end, [], M).

histogram_lines(M) ->
    maps:fold(fun(K, Summary, Acc) ->
        N = prom_bin(K),
        P50 = prom_bin(maps:get(p50, Summary, 0)),
        P95 = prom_bin(maps:get(p95, Summary, 0)),
        P99 = prom_bin(maps:get(p99, Summary, 0)),
        Cnt = prom_bin(maps:get(count, Summary, 0)),
        Acc ++ [
            <<"# TYPE ", N/binary, " summary">>,
            <<N/binary, "{quantile=\"0.5\"} ",  P50/binary>>,
            <<N/binary, "{quantile=\"0.95\"} ", P95/binary>>,
            <<N/binary, "{quantile=\"0.99\"} ", P99/binary>>,
            <<N/binary, "_count ", Cnt/binary>>
        ]
    end, [], M).

http_lines(M) when map_size(M) =:= 0 -> [];
http_lines(M) ->
    Endpoints = maps:fold(fun(Key, Stats, Acc) ->
        Label = <<"endpoint=\"", Key/binary, "\"">>,
        Acc ++ [
            <<"http_requests_total{", Label/binary, "} ",
              (prom_bin(maps:get(count, Stats)))/binary>>,
            <<"http_errors_total{",   Label/binary, "} ",
              (prom_bin(maps:get(errors, Stats)))/binary>>,
            <<"http_request_duration_ms{", Label/binary, ",quantile=\"0.95\"} ",
              (prom_bin(maps:get(p95_ms, Stats)))/binary>>
        ]
    end, [], M),
    [<<"# TYPE http_requests_total counter">>,
     <<"# TYPE http_errors_total counter">>,
     <<"# TYPE http_request_duration_ms summary">>] ++ Endpoints.

beam_lines(B) ->
    [
        <<"# TYPE beam_process_count gauge">>,
        <<"beam_process_count ",          (prom_bin(maps:get(process_count, B)))/binary>>,
        <<"# TYPE beam_memory_total_bytes gauge">>,
        <<"beam_memory_total_bytes ",     (prom_bin(maps:get(memory_total, B)))/binary>>,
        <<"# TYPE beam_memory_processes_bytes gauge">>,
        <<"beam_memory_processes_bytes ", (prom_bin(maps:get(memory_processes, B)))/binary>>,
        <<"# TYPE beam_memory_ets_bytes gauge">>,
        <<"beam_memory_ets_bytes ",       (prom_bin(maps:get(memory_ets, B)))/binary>>,
        <<"# TYPE beam_uptime_ms gauge">>,
        <<"beam_uptime_ms ",              (prom_bin(maps:get(uptime_ms, B)))/binary>>
    ].

prom_bin(V) when is_binary(V)  -> V;
prom_bin(V) when is_atom(V)    -> atom_to_binary(V, utf8);
prom_bin(V) when is_integer(V) -> integer_to_binary(V);
prom_bin(V) when is_float(V)   -> float_to_binary(V, [{decimals, 3}, compact]).

%% ── Internal ────────────────────────────────────────────────────────────────

percentile(_, 0, _) -> 0;
percentile(Sorted, Len, P) ->
    Index = max(1, min(Len, round(P / 100 * Len))),
    lists:nth(Index, Sorted).

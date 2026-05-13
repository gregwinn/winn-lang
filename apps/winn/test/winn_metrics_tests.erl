%% winn_metrics_tests.erl
%% Tests for the metrics module (#36).

-module(winn_metrics_tests).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    winn_metrics:enable(),
    winn_metrics:reset_all().

%% ── Counters ────────────────────────────────────────────────────────────────

counter_increment_test() ->
    setup(),
    winn_metrics:increment(requests),
    winn_metrics:increment(requests),
    winn_metrics:increment(requests),
    ?assertEqual(3, winn_metrics:get(requests)).

counter_increment_by_test() ->
    setup(),
    winn_metrics:increment(bytes, 100),
    winn_metrics:increment(bytes, 250),
    ?assertEqual(350, winn_metrics:get(bytes)).

%% ── Gauges ──────────────────────────────────────────────────────────────────

gauge_set_test() ->
    setup(),
    winn_metrics:set(queue_depth, 42),
    ?assertEqual(42, winn_metrics:get(queue_depth)).

gauge_overwrite_test() ->
    setup(),
    winn_metrics:set(active, 10),
    winn_metrics:set(active, 25),
    ?assertEqual(25, winn_metrics:get(active)).

%% ── Histograms ──────────────────────────────────────────────────────────────

histogram_observe_test() ->
    setup(),
    winn_metrics:observe(latency, 10),
    winn_metrics:observe(latency, 20),
    winn_metrics:observe(latency, 30),
    #{histograms := Histograms} = winn_metrics:snapshot(),
    #{latency := Stats} = Histograms,
    ?assertEqual(3, maps:get(count, Stats)),
    ?assertEqual(10, maps:get(min, Stats)),
    ?assertEqual(30, maps:get(max, Stats)).

%% ── Timer ───────────────────────────────────────────────────────────────────

timer_test() ->
    setup(),
    Result = winn_metrics:time(db_query, fun() ->
        timer:sleep(5),
        42
    end),
    ?assertEqual(42, Result),
    #{histograms := Histograms} = winn_metrics:snapshot(),
    #{db_query := Stats} = Histograms,
    ?assertEqual(1, maps:get(count, Stats)),
    ?assert(maps:get(avg, Stats) >= 4). %% at least 4ms

%% ── HTTP Metrics ────────────────────────────────────────────────────────────

http_record_test() ->
    setup(),
    winn_metrics:record_http(<<"GET">>, <<"/api/users">>, 200, 12),
    winn_metrics:record_http(<<"GET">>, <<"/api/users">>, 200, 18),
    winn_metrics:record_http(<<"GET">>, <<"/api/users">>, 500, 45),
    Snap = winn_metrics:http_snapshot(),
    #{<<"GET /api/users">> := Stats} = Snap,
    ?assertEqual(3, maps:get(count, Stats)),
    ?assertEqual(1, maps:get(errors, Stats)),
    ?assertEqual(25, maps:get(avg_ms, Stats)).

%% ── Snapshot ────────────────────────────────────────────────────────────────

snapshot_test() ->
    setup(),
    winn_metrics:increment(req_count, 5),
    winn_metrics:set(conn_active, 3),
    #{counters := Counters, gauges := Gauges} = winn_metrics:snapshot(),
    ?assertEqual(5, maps:get(req_count, Counters)),
    ?assertEqual(3, maps:get(conn_active, Gauges)).

%% ── BEAM Stats ──────────────────────────────────────────────────────────────

beam_stats_test() ->
    Stats = winn_metrics:beam_stats(),
    ?assert(maps:get(process_count, Stats) > 0),
    ?assert(maps:get(memory_total, Stats) > 0),
    ?assert(maps:get(scheduler_count, Stats) > 0).

%% ── Reset ───────────────────────────────────────────────────────────────────

reset_test() ->
    setup(),
    winn_metrics:increment(temp, 10),
    winn_metrics:reset(temp),
    ?assertEqual(0, winn_metrics:get(temp)).

reset_all_test() ->
    setup(),
    winn_metrics:increment(a, 1),
    winn_metrics:set(b, 2),
    winn_metrics:reset_all(),
    ?assertEqual(0, winn_metrics:get(a)),
    ?assertEqual(0, winn_metrics:get(b)).

%% ── Prometheus exposition format (#156) ─────────────────────────────────────

prometheus_contains(Output, Substr) ->
    binary:match(Output, list_to_binary(Substr)) =/= nomatch.

prometheus_counter_test() ->
    setup(),
    winn_metrics:increment(orders_total, 3),
    Out = winn_metrics:prometheus(),
    ?assert(prometheus_contains(Out, "# TYPE orders_total counter")),
    ?assert(prometheus_contains(Out, "orders_total 3")).

prometheus_gauge_test() ->
    setup(),
    winn_metrics:set(queue_depth, 7),
    Out = winn_metrics:prometheus(),
    ?assert(prometheus_contains(Out, "# TYPE queue_depth gauge")),
    ?assert(prometheus_contains(Out, "queue_depth 7")).

prometheus_histogram_test() ->
    setup(),
    winn_metrics:observe(request_ms, 10),
    winn_metrics:observe(request_ms, 20),
    Out = winn_metrics:prometheus(),
    ?assert(prometheus_contains(Out, "# TYPE request_ms summary")),
    ?assert(prometheus_contains(Out, "request_ms{quantile=\"0.5\"}")),
    ?assert(prometheus_contains(Out, "request_ms{quantile=\"0.95\"}")),
    ?assert(prometheus_contains(Out, "request_ms{quantile=\"0.99\"}")),
    ?assert(prometheus_contains(Out, "request_ms_count 2")).

prometheus_http_labels_test() ->
    setup(),
    winn_metrics:record_http(<<"GET">>, <<"/users">>, 200, 5),
    winn_metrics:record_http(<<"GET">>, <<"/users">>, 500, 12),
    Out = winn_metrics:prometheus(),
    ?assert(prometheus_contains(Out, "# TYPE http_requests_total counter")),
    ?assert(prometheus_contains(Out, "# TYPE http_request_duration_ms summary")),
    ?assert(prometheus_contains(Out, "http_requests_total{endpoint=\"GET /users\"} 2")),
    ?assert(prometheus_contains(Out, "http_errors_total{endpoint=\"GET /users\"} 1")),
    ?assert(prometheus_contains(Out, "http_request_duration_ms{endpoint=\"GET /users\",quantile=\"0.95\"}")).

prometheus_beam_stats_test() ->
    setup(),
    Out = winn_metrics:prometheus(),
    ?assert(prometheus_contains(Out, "# TYPE beam_process_count gauge")),
    ?assert(prometheus_contains(Out, "beam_process_count ")),
    ?assert(prometheus_contains(Out, "beam_memory_total_bytes ")),
    ?assert(prometheus_contains(Out, "beam_memory_processes_bytes ")),
    ?assert(prometheus_contains(Out, "beam_memory_ets_bytes ")),
    ?assert(prometheus_contains(Out, "beam_uptime_ms ")).

%% Float values use 3-decimal compact form so trailing zeros never appear.
prometheus_float_compact_test() ->
    setup(),
    winn_metrics:observe(latency, 12.3),
    Out = winn_metrics:prometheus(),
    ?assert(prometheus_contains(Out, "latency{quantile=\"0.5\"} 12.3")),
    ?assertEqual(nomatch, binary:match(Out, <<"12.300">>)).

%% Output is a valid binary, ends in a newline, and starts with no leading
%% whitespace — basic shape Prometheus scrapers expect.
prometheus_shape_test() ->
    setup(),
    Out = winn_metrics:prometheus(),
    ?assert(is_binary(Out)),
    ?assertEqual($\n, binary:last(Out)),
    ?assertNotEqual(<<" ">>, binary:part(Out, 0, 1)).

%% Empty HTTP map → no http_* lines (avoids emitting orphan TYPE lines).
prometheus_no_http_when_empty_test() ->
    setup(),
    Out = winn_metrics:prometheus(),
    ?assertEqual(nomatch, binary:match(Out, <<"http_requests_total">>)).

%% ── End-to-end: Metrics from Winn source ───────────────────────────────────

metrics_from_winn_test() ->
    setup(),
    Source = "module MetricsTest\n"
             "  def run()\n"
             "    Metrics.enable()\n"
             "    Metrics.increment(:api_calls)\n"
             "    Metrics.increment(:api_calls)\n"
             "    Metrics.set(:active_users, 42)\n"
             "    Metrics.get(:api_calls)\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST} = winn_parser:parse(Tokens),
    Transformed = winn_transform:transform(AST),
    [CoreMod] = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    Result = ModName:run(),
    ?assertEqual(2, Result).

%% End-to-end: a Winn handler can call Metrics.prometheus() (#156).
prometheus_from_winn_test() ->
    setup(),
    winn_metrics:increment(orders_total, 5),
    winn_metrics:set(queue_depth, 3),
    Source = "module PromTest\n"
             "  def run()\n"
             "    Metrics.prometheus()\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST} = winn_parser:parse(Tokens),
    Transformed = winn_transform:transform(AST),
    [CoreMod] = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    Result = ModName:run(),
    ?assert(is_binary(Result)),
    ?assert(binary:match(Result, <<"orders_total 5">>) =/= nomatch),
    ?assert(binary:match(Result, <<"queue_depth 3">>) =/= nomatch).

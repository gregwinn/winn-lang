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

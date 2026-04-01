%% winn_bench_tests.erl
%% Tests for built-in load testing (#35).

-module(winn_bench_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── CLI parse ───────────────────────────────────────────────────────────────

parse_bench_test() ->
    ?assertEqual({bench, ["bench/api.winn"]},
                 winn_cli:parse_args(["bench", "bench/api.winn"])).

%% ── Percentile calculation ──────────────────────────────────────────────────

percentile_empty_test() ->
    ?assertEqual(0, winn_bench:percentile([], 0, 50)).

percentile_single_test() ->
    ?assertEqual(42, winn_bench:percentile([42], 1, 50)).

percentile_p50_test() ->
    Sorted = lists:seq(1, 100),
    ?assertEqual(50, winn_bench:percentile(Sorted, 100, 50)).

percentile_p99_test() ->
    Sorted = lists:seq(1, 100),
    ?assertEqual(99, winn_bench:percentile(Sorted, 100, 99)).

%% ── Run a simple benchmark ──────────────────────────────────────────────────

run_simple_bench_test() ->
    Counter = counters:new(1, []),
    Results = winn_bench:run(test_bench, #{concurrent => 2, duration => 1}, fun() ->
        counters:add(Counter, 1, 1),
        ok
    end),
    ?assert(maps:get(total, Results) > 0),
    ?assert(maps:get(avg, Results) >= 0),
    ?assertEqual(0, maps:get(errors, Results)),
    ?assert(maps:get(p50, Results) >= 0),
    ?assert(maps:get(p99, Results) >= 0).

%% ── Bench with errors ───────────────────────────────────────────────────────

run_bench_with_errors_test() ->
    Counter = counters:new(1, []),
    Results = winn_bench:run(error_bench, #{concurrent => 1, duration => 1}, fun() ->
        counters:add(Counter, 1, 1),
        case counters:get(Counter, 1) rem 3 of
            0 -> error(intentional);
            _ -> ok
        end
    end),
    ?assert(maps:get(errors, Results) > 0),
    ?assert(maps:get(error_rate, Results) > 0).

%% ── Format results ──────────────────────────────────────────────────────────

format_results_test() ->
    R = #{name => test, total => 100, rps => 50,
          avg => 10, p50 => 8, p95 => 20, p99 => 30,
          min => 2, max => 45, errors => 1, error_rate => 1.0},
    Formatted = lists:flatten(winn_bench:format_results(R)),
    ?assert(string:find(Formatted, "100 reqs") =/= nomatch),
    ?assert(string:find(Formatted, "50/s") =/= nomatch).

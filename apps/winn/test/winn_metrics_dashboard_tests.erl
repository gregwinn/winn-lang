%% winn_metrics_dashboard_tests.erl
%% Tests for the live metrics dashboard (#37).

-module(winn_metrics_dashboard_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── CLI parse ───────────────────────────────────────────────────────────────

parse_metrics_test() ->
    ?assertEqual({metrics, []}, winn_cli:parse_args(["metrics"])).

parse_metrics_snapshot_test() ->
    ?assertEqual({metrics, ["--snapshot"]}, winn_cli:parse_args(["metrics", "--snapshot"])).

%% ── Dashboard rendering ────────────────────────────────────────────────────

dashboard_contains_title_test() ->
    winn_metrics:enable(),
    winn_metrics:reset_all(),
    State = #{
        snapshot => winn_metrics:snapshot(),
        http => winn_metrics:http_snapshot(),
        beam => winn_metrics:beam_stats(),
        uptime => 120,
        prev_snapshot => nil
    },
    Output = lists:flatten(winn_metrics_dashboard:format_dashboard(State)),
    ?assert(string:find(Output, "Winn Metrics") =/= nomatch).

dashboard_shows_beam_stats_test() ->
    winn_metrics:enable(),
    State = #{
        snapshot => winn_metrics:snapshot(),
        http => winn_metrics:http_snapshot(),
        beam => winn_metrics:beam_stats(),
        uptime => 60,
        prev_snapshot => nil
    },
    Output = lists:flatten(winn_metrics_dashboard:format_dashboard(State)),
    ?assert(string:find(Output, "BEAM") =/= nomatch),
    ?assert(string:find(Output, "Processes") =/= nomatch),
    ?assert(string:find(Output, "Memory") =/= nomatch).

dashboard_shows_http_metrics_test() ->
    winn_metrics:enable(),
    winn_metrics:reset_all(),
    winn_metrics:record_http(<<"GET">>, <<"/api/users">>, 200, 15),
    winn_metrics:record_http(<<"GET">>, <<"/api/users">>, 200, 25),
    State = #{
        snapshot => winn_metrics:snapshot(),
        http => winn_metrics:http_snapshot(),
        beam => winn_metrics:beam_stats(),
        uptime => 30,
        prev_snapshot => nil
    },
    Output = lists:flatten(winn_metrics_dashboard:format_dashboard(State)),
    ?assert(string:find(Output, "GET /api/users") =/= nomatch),
    ?assert(string:find(Output, "2 req") =/= nomatch).

dashboard_shows_custom_metrics_test() ->
    winn_metrics:enable(),
    winn_metrics:reset_all(),
    winn_metrics:increment(orders_created, 47),
    winn_metrics:set(queue_depth, 3),
    State = #{
        snapshot => winn_metrics:snapshot(),
        http => winn_metrics:http_snapshot(),
        beam => winn_metrics:beam_stats(),
        uptime => 90,
        prev_snapshot => nil
    },
    Output = lists:flatten(winn_metrics_dashboard:format_dashboard(State)),
    ?assert(string:find(Output, "orders_created") =/= nomatch),
    ?assert(string:find(Output, "queue_depth") =/= nomatch).

dashboard_shows_uptime_test() ->
    winn_metrics:enable(),
    State = #{
        snapshot => winn_metrics:snapshot(),
        http => #{},
        beam => winn_metrics:beam_stats(),
        uptime => 3700,
        prev_snapshot => nil
    },
    Output = lists:flatten(winn_metrics_dashboard:format_dashboard(State)),
    ?assert(string:find(Output, "1h") =/= nomatch).

%% winn_watch_tests.erl
%% Tests for the file watcher and live dashboard (#11).

-module(winn_watch_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Format helpers ──────────────────────────────────────────────────────────

format_elapsed_just_now_test() ->
    ?assertEqual("just now", lists:flatten(winn_watch:format_elapsed(0))).

format_elapsed_seconds_test() ->
    ?assertEqual("5s ago", lists:flatten(winn_watch:format_elapsed(5))).

format_elapsed_minutes_test() ->
    ?assertEqual("2m 30s ago", lists:flatten(winn_watch:format_elapsed(150))).

format_elapsed_hours_test() ->
    ?assertEqual("1h 5m ago", lists:flatten(winn_watch:format_elapsed(3900))).

format_uptime_seconds_test() ->
    ?assertEqual("45s", lists:flatten(winn_watch:format_uptime(45))).

format_uptime_minutes_test() ->
    ?assertEqual("3m 15s", lists:flatten(winn_watch:format_uptime(195))).

format_uptime_hours_test() ->
    ?assertEqual("2h 10m", lists:flatten(winn_watch:format_uptime(7800))).

%% ── Dashboard rendering ────────────────────────────────────────────────────

dashboard_contains_module_names_test() ->
    Now = erlang:monotonic_time(second),
    State = #{
        modules    => #{myapp => {ok, Now}, auth => {ok, Now - 5}},
        reloads    => 3,
        errors     => 0,
        start_time => Now - 60,
        files      => #{}
    },
    Output = lists:flatten(winn_watch:format_dashboard(State)),
    ?assert(string:find(Output, "myapp") =/= nomatch),
    ?assert(string:find(Output, "auth") =/= nomatch).

dashboard_shows_error_test() ->
    Now = erlang:monotonic_time(second),
    State = #{
        modules    => #{broken => {error, "line 5: syntax error", Now}},
        reloads    => 1,
        errors     => 1,
        start_time => Now - 30,
        files      => #{}
    },
    Output = lists:flatten(winn_watch:format_dashboard(State)),
    ?assert(string:find(Output, "broken") =/= nomatch),
    ?assert(string:find(Output, "compile error") =/= nomatch),
    ?assert(string:find(Output, "syntax error") =/= nomatch).

dashboard_shows_stats_test() ->
    Now = erlang:monotonic_time(second),
    State = #{
        modules    => #{app => {ok, Now}},
        reloads    => 7,
        errors     => 0,
        start_time => Now - 120,
        files      => #{}
    },
    Output = lists:flatten(winn_watch:format_dashboard(State)),
    ?assert(string:find(Output, "Reloads: 7") =/= nomatch),
    ?assert(string:find(Output, "Errors: 0") =/= nomatch),
    ?assert(string:find(Output, "Uptime:") =/= nomatch).

dashboard_shows_winn_watch_title_test() ->
    Now = erlang:monotonic_time(second),
    State = #{
        modules    => #{},
        reloads    => 0,
        errors     => 0,
        start_time => Now,
        files      => #{}
    },
    Output = lists:flatten(winn_watch:format_dashboard(State)),
    ?assert(string:find(Output, "Winn Watch") =/= nomatch).

%% ── File change detection ───────────────────────────────────────────────────

check_files_detects_no_changes_test() ->
    %% With no files in state and no .winn files in cwd, should return []
    State = #{files => #{"nonexistent.winn" => 99999999999}},
    Changed = winn_watch:check_files(State),
    ?assertEqual([], Changed).

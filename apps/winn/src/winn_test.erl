%% winn_test.erl
%% Testing framework runtime: assertions and test runner.

-module(winn_test).
-export([assert/1, assert_equal/2, run_tests/1]).

%% ── Assertions ───────────────────────────────────────────────────────────────

assert(true) -> ok;
assert(false) ->
    error({assertion_failed, #{expected => true, got => false}});
assert(Val) ->
    error({assertion_failed, #{expected => true, got => Val}}).

assert_equal(Expected, Actual) when Expected =:= Actual -> ok;
assert_equal(Expected, Actual) ->
    error({assertion_failed, #{expected => Expected, got => Actual}}).

%% ── Test Runner ──────────────────────────────────────────────────────────────

-spec run_tests([module()]) -> ok | error.
run_tests(Modules) ->
    StartTime = erlang:monotonic_time(millisecond),
    Results = lists:flatmap(fun run_module/1, Modules),
    EndTime = erlang:monotonic_time(millisecond),
    Elapsed = EndTime - StartTime,
    format_results(Results, Elapsed).

%% ── Internal ─────────────────────────────────────────────────────────────────

run_module(Mod) ->
    Exports = Mod:module_info(exports),
    TestFuns = [F || {F, 0} <- Exports, is_test_function(F)],
    [run_one(Mod, F) || F <- TestFuns].

is_test_function(Name) ->
    case atom_to_list(Name) of
        "test_" ++ _ -> true;
        _ -> false
    end.

run_one(Mod, Fun) ->
    try
        Mod:Fun(),
        {pass, Mod, Fun}
    catch
        error:{assertion_failed, Info} ->
            {fail, Mod, Fun, {assertion_failed, Info}};
        Class:Reason:Stack ->
            {fail, Mod, Fun, {Class, Reason, Stack}}
    end.

format_results(Results, Elapsed) ->
    UseColor = use_color(),
    Passes = [R || {pass, _, _} = R <- Results],
    Fails  = [R || {fail, _, _, _} = R <- Results],
    PassCount = length(Passes),
    FailCount = length(Fails),
    Total = PassCount + FailCount,

    %% Print each result
    lists:foreach(fun(R) -> print_result(R, UseColor) end, Results),

    %% Print summary
    io:format("~n"),
    if FailCount > 0 ->
        io:format("~sFailed ~B of ~B tests~s (~Bms)~n",
                  [color(red, UseColor), FailCount, Total,
                   color(reset, UseColor), Elapsed]);
       true ->
        io:format("~s~B tests, 0 failures~s (~Bms)~n",
                  [color(green, UseColor), Total,
                   color(reset, UseColor), Elapsed])
    end,

    case FailCount of
        0 -> ok;
        _ -> error
    end.

print_result({pass, Mod, Fun}, UseColor) ->
    io:format("  ~s.~s ~n", [color(green, UseColor), color(reset, UseColor)]),
    io:format("    ~s:~s~n", [Mod, Fun]);
print_result({fail, Mod, Fun, {assertion_failed, Info}}, UseColor) ->
    io:format("  ~sF~s ~s:~s~n",
              [color(red, UseColor), color(reset, UseColor), Mod, Fun]),
    case maps:find(expected, Info) of
        {ok, Expected} ->
            Actual = maps:get(got, Info, undefined),
            io:format("    expected: ~p~n", [Expected]),
            io:format("         got: ~p~n", [Actual]);
        error -> ok
    end;
print_result({fail, Mod, Fun, {Class, Reason, _Stack}}, UseColor) ->
    io:format("  ~sF~s ~s:~s~n",
              [color(red, UseColor), color(reset, UseColor), Mod, Fun]),
    io:format("    ~s:~p~n", [Class, Reason]).

%% ── Color helpers ────────────────────────────────────────────────────────────

use_color() ->
    case os:getenv("NO_COLOR") of
        false -> is_tty();
        _ -> false
    end.

is_tty() ->
    case os:type() of
        {unix, _} ->
            case io:columns() of
                {ok, _} -> true;
                _ -> false
            end;
        _ -> false
    end.

color(green, true) -> "\e[32m";
color(red, true)   -> "\e[31m";
color(reset, true) -> "\e[0m";
color(_, false)    -> "".

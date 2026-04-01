-module(winn_health).
-export([liveness/1, readiness/2, detailed/2, check/2]).

%% Health.liveness(conn) — always returns 200 (proves the VM is running)
liveness(Conn) ->
    winn_server:json(Conn, #{status => <<"ok">>}).

%% Health.readiness(conn, Checks) — returns 200 if all checks pass, 503 if any fail
%% Checks = [Health.check(:database, fn() => Repo.execute("SELECT 1") end)]
readiness(Conn, Checks) ->
    Results = run_checks(Checks),
    AllUp = lists:all(fun({_, Status, _}) -> Status =:= up end, Results),
    Status = case AllUp of true -> 200; false -> 503 end,
    Body = #{
        status => case AllUp of true -> <<"healthy">>; false -> <<"unhealthy">> end,
        checks => format_checks(Results)
    },
    winn_server:json(Conn, Body, Status).

%% Health.detailed(conn, Checks) — full health report with latencies
detailed(Conn, Checks) ->
    Results = run_checks(Checks),
    AllUp = lists:all(fun({_, Status, _}) -> Status =:= up end, Results),
    Uptime = erlang:monotonic_time(second) - erlang:system_info(start_time),
    Status = case AllUp of true -> 200; false -> 503 end,
    Body = #{
        status => case AllUp of true -> <<"healthy">>; false -> <<"unhealthy">> end,
        uptime => Uptime,
        checks => format_checks(Results)
    },
    winn_server:json(Conn, Body, Status).

%% Health.check(:name, Fun) — creates a check tuple
check(Name, Fun) when is_atom(Name), is_function(Fun, 0) ->
    {Name, Fun}.

%% ── Internal ────────────────────────────────────────────────────────────────

run_checks(Checks) ->
    [run_one_check(C) || C <- Checks].

run_one_check({Name, Fun}) ->
    Start = erlang:monotonic_time(microsecond),
    Result = try Fun(), ok catch _:_ -> error end,
    Elapsed = (erlang:monotonic_time(microsecond) - Start) / 1000,
    case Result of
        ok    -> {Name, up, Elapsed};
        error -> {Name, down, Elapsed}
    end.

format_checks(Results) ->
    maps:from_list([{Name, #{status => Status, latency_ms => round(Ms)}}
                    || {Name, Status, Ms} <- Results]).

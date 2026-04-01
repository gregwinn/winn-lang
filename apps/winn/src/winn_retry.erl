-module(winn_retry).
-export([run/2]).

%% Retry.run(%{max: 3, base_delay: 1000, max_delay: 30000}, Fun)
run(Opts, Fun) when is_function(Fun, 0) ->
    Max = maps:get(max, Opts, 3),
    BaseDelay = maps:get(base_delay, Opts, 1000),
    MaxDelay = maps:get(max_delay, Opts, 30000),
    retry_loop(Fun, 0, Max, BaseDelay, MaxDelay).

retry_loop(Fun, Attempt, Max, _BaseDelay, _MaxDelay) when Attempt >= Max ->
    try
        {ok, Fun()}
    catch
        _:Reason -> {error, {retries_exhausted, Reason}}
    end;
retry_loop(Fun, Attempt, Max, BaseDelay, MaxDelay) ->
    try
        {ok, Fun()}
    catch
        _:_Reason ->
            Delay = min(MaxDelay, BaseDelay * (1 bsl Attempt)),
            Jitter = case Delay div 4 of 0 -> 0; N -> rand:uniform(N) end,
            timer:sleep(Delay + Jitter),
            retry_loop(Fun, Attempt + 1, Max, BaseDelay, MaxDelay)
    end.

-module(winn_timer).
-export([every/3, 'after'/3, cancel/1, sleep/1]).

%% Timer.sleep(Ms) — block the calling process.
sleep(Ms) when is_integer(Ms), Ms >= 0 ->
    timer:sleep(Ms),
    ok.

%% Timer.every(N, :seconds/:ms, Fun)
every(N, Unit, Fun) when is_function(Fun, 0) ->
    Ms = to_ms(N, Unit),
    {ok, TRef} = timer:apply_interval(Ms, erlang, apply, [Fun, []]),
    TRef.

%% Timer.after(N, :seconds/:ms, Fun)
'after'(N, Unit, Fun) when is_function(Fun, 0) ->
    Ms = to_ms(N, Unit),
    {ok, TRef} = timer:apply_after(Ms, erlang, apply, [Fun, []]),
    TRef.

cancel(TRef) ->
    timer:cancel(TRef),
    ok.

to_ms(N, seconds) -> N * 1000;
to_ms(N, ms)      -> N;
to_ms(N, minutes) -> N * 60 * 1000.

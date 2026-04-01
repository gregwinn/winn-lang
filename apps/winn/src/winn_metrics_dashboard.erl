%% winn_metrics_dashboard.erl
%% Live terminal dashboard for metrics — like winn watch but for observability.

-module(winn_metrics_dashboard).
-export([start/1, format_dashboard/1]).

-define(REFRESH_INTERVAL, 1000).

%% ── Public API ───────────────────────────────────────────────────────────────

start(Opts) ->
    winn_metrics:enable(),
    StartTime = erlang:monotonic_time(second),
    io:format("\e[2J\e[H"),
    State = #{start_time => StartTime, prev_snapshot => nil, opts => Opts},
    loop(State).

%% ── Main loop ───────────────────────────────────────────────────────────────

loop(State) ->
    Snapshot = winn_metrics:snapshot(),
    HttpSnap = winn_metrics:http_snapshot(),
    BeamStats = winn_metrics:beam_stats(),
    StartTime = maps:get(start_time, State),
    Now = erlang:monotonic_time(second),
    Uptime = Now - StartTime,

    DashState = #{
        snapshot => Snapshot,
        http => HttpSnap,
        beam => BeamStats,
        uptime => Uptime,
        prev_snapshot => maps:get(prev_snapshot, State, nil)
    },

    Output = format_dashboard(DashState),
    io:format("\e[H~ts", [Output]),

    timer:sleep(?REFRESH_INTERVAL),
    loop(State#{prev_snapshot => Snapshot}).

%% ── Dashboard rendering ─────────────────────────────────────────────────────

format_dashboard(#{snapshot := Snap, http := HttpSnap, beam := Beam, uptime := Uptime}) ->
    Width = 60,
    #{counters := Counters, gauges := Gauges} = Snap,

    %% Header
    Title = " Winn Metrics ",
    PadLen = Width - length(Title) - 2,
    Header = io_lib:format("\e[1m~ts~ts~ts~ts\e[0m~n",
        [[$\x{250C}, $\x{2500}], Title,
         lists:duplicate(max(0, PadLen), $\x{2500}), [$\x{2510}]]),

    %% Uptime line
    UptimeLine = pad_line(io_lib:format(" Uptime: ~ts", [format_uptime(Uptime)]), Width),

    BlankLine = pad_line("", Width),

    %% HTTP section
    HttpLines = case maps:size(HttpSnap) of
        0 ->
            [pad_line(" HTTP: no requests recorded", Width)];
        _ ->
            TotalReqs = lists:sum([maps:get(count, V) || {_, V} <- maps:to_list(HttpSnap)]),
            TotalErrs = lists:sum([maps:get(errors, V) || {_, V} <- maps:to_list(HttpSnap)]),
            SummaryLine = pad_line(
                io_lib:format(" HTTP  Requests: ~B  Errors: ~B", [TotalReqs, TotalErrs]), Width),
            Sorted = lists:reverse(lists:sort(
                fun({_, A}, {_, B}) -> maps:get(count, A) < maps:get(count, B) end,
                maps:to_list(HttpSnap))),
            Top = lists:sublist(Sorted, 5),
            EndpointLines = [begin
                Count = maps:get(count, Stats),
                AvgMs = maps:get(avg_ms, Stats),
                Errs = maps:get(errors, Stats),
                pad_line(io_lib:format("   ~ts  ~B req  ~Bms avg  ~B err",
                    [pad_right(binary_to_list(Key), 25), Count, AvgMs, Errs]), Width)
            end || {Key, Stats} <- Top],
            [SummaryLine, BlankLine | EndpointLines]
    end,

    %% BEAM section
    ProcCount = maps:get(process_count, Beam),
    ProcLimit = maps:get(process_limit, Beam),
    MemMB = maps:get(memory_total, Beam) div (1024 * 1024),
    Schedulers = maps:get(scheduler_count, Beam),
    BeamLines = [
        pad_line(io_lib:format(" BEAM  Processes: ~B/~B  Memory: ~BMB  Schedulers: ~B",
            [ProcCount, ProcLimit, MemMB, Schedulers]), Width)
    ],

    %% Custom counters/gauges
    CustomLines = case {maps:size(Counters), maps:size(Gauges)} of
        {0, 0} -> [];
        _ ->
            CounterEntries = [io_lib:format("~s: ~B", [K, V]) || {K, V} <- maps:to_list(Counters)],
            GaugeEntries = [io_lib:format("~s: ~p", [K, V]) || {K, V} <- maps:to_list(Gauges)],
            AllEntries = CounterEntries ++ GaugeEntries,
            case AllEntries of
                [] -> [];
                _ ->
                    [BlankLine,
                     pad_line(" Custom Metrics", Width) |
                     [pad_line(io_lib:format("   ~ts", [E]), Width) || E <- lists:sublist(AllEntries, 6)]]
            end
    end,

    %% Bottom border
    Bottom = io_lib:format("\e[1m~ts~ts~ts\e[0m~n",
        [[$\x{2514}], lists:duplicate(Width - 2, $\x{2500}), [$\x{2518}]]),

    lists:flatten([Header, UptimeLine, BlankLine] ++
                  HttpLines ++ [BlankLine] ++
                  BeamLines ++
                  CustomLines ++
                  [BlankLine, Bottom]).

%% ── Helpers ──────────────────────────────────────────────────────────────────

format_uptime(Secs) when Secs < 60 ->
    io_lib:format("~Bs", [Secs]);
format_uptime(Secs) when Secs < 3600 ->
    io_lib:format("~Bm ~Bs", [Secs div 60, Secs rem 60]);
format_uptime(Secs) ->
    io_lib:format("~Bh ~Bm", [Secs div 3600, (Secs rem 3600) div 60]).

pad_line(Text, Width) ->
    Flat = lists:flatten(Text),
    VisLen = visible_length(Flat),
    Pad = max(0, Width - 2 - VisLen),
    io_lib:format("\x{2502}~ts~ts\x{2502}~n", [Flat, lists:duplicate(Pad, $\s)]).

visible_length(Str) ->
    Re = "\e\\[[0-9;]*m",
    Stripped = re:replace(Str, Re, "", [global, unicode, {return, list}]),
    string:length(Stripped).

pad_right(Str, Width) ->
    Len = string:length(Str),
    case Len >= Width of
        true  -> string:slice(Str, 0, Width);
        false -> Str ++ lists:duplicate(Width - Len, $\s)
    end.

%% winn_watch.erl
%% File watcher with hot code reloading and live terminal dashboard.

-module(winn_watch).
-export([start/1, format_dashboard/1, check_files/1, format_elapsed/1, format_uptime/1]).

-define(POLL_INTERVAL, 500).
-define(REDRAW_INTERVAL, 1000).

%% ── Public API ───────────────────────────────────────────────────────────────

-spec start(#{start => boolean()}) -> no_return().
start(Opts) ->
    OutDir = "ebin",
    ok = filelib:ensure_path(OutDir),
    code:add_patha(OutDir),

    %% Initial compile
    Files = discover_files(),
    case Files of
        [] ->
            io:format("No .winn files found in src/ or current directory.~n"),
            halt(1);
        _ -> ok
    end,

    {Modules, Mtimes} = initial_compile(Files, OutDir),

    %% Optionally start the app
    case maps:get(start, Opts, false) of
        true  -> start_app(Files);
        false -> ok
    end,

    State = #{
        files      => Mtimes,
        modules    => Modules,
        reloads    => 0,
        errors     => count_errors(Modules),
        start_time => erlang:monotonic_time(second),
        out_dir    => OutDir,
        last_draw  => 0
    },

    %% Clear screen and enter watch loop
    io:format("\e[2J\e[H"),
    watch_loop(State).

%% ── Watch loop ──────────────────────────────────────────────────────────────

watch_loop(State) ->
    Now = erlang:monotonic_time(second),
    LastDraw = maps:get(last_draw, State),

    %% Redraw dashboard every second
    State2 = case (Now - LastDraw) >= 1 of
        true ->
            draw_dashboard(State),
            State#{last_draw => Now};
        false ->
            State
    end,

    timer:sleep(?POLL_INTERVAL),

    %% Check for file changes
    ChangedFiles = check_files(State2),
    State3 = lists:foldl(fun(File, S) ->
        recompile_and_reload(File, S)
    end, State2, ChangedFiles),

    %% Update mtimes
    State4 = update_mtimes(State3),

    watch_loop(State4).

%% ── File discovery and mtime tracking ───────────────────────────────────────

discover_files() ->
    SrcFiles = filelib:wildcard("src/*.winn"),
    case SrcFiles of
        [] -> filelib:wildcard("*.winn");
        _  -> SrcFiles
    end.

get_mtime(File) ->
    case file:read_file_info(File, [{time, posix}]) of
        {ok, Info} -> element(6, Info);  % mtime field in file_info
        _ -> 0
    end.

check_files(#{files := Mtimes}) ->
    CurrentFiles = discover_files(),
    lists:filter(fun(File) ->
        CurrentMtime = get_mtime(File),
        case maps:get(File, Mtimes, undefined) of
            undefined    -> true;   % new file
            OldMtime     -> CurrentMtime > OldMtime
        end
    end, CurrentFiles).

update_mtimes(#{files := Mtimes} = State) ->
    CurrentFiles = discover_files(),
    NewMtimes = lists:foldl(fun(File, Acc) ->
        maps:put(File, get_mtime(File), Acc)
    end, Mtimes, CurrentFiles),
    State#{files => NewMtimes}.

%% ── Compilation and hot reload ──────────────────────────────────────────────

initial_compile(Files, OutDir) ->
    lists:foldl(fun(File, {Mods, Mtimes}) ->
        Mtime = get_mtime(File),
        ModName = detect_module(File),
        case winn:compile_file(File, OutDir) of
            {ok, _} ->
                code:purge(ModName),
                code:load_file(ModName),
                {maps:put(ModName, {ok, erlang:monotonic_time(second)}, Mods),
                 maps:put(File, Mtime, Mtimes)};
            {error, Reason} ->
                ErrMsg = format_error(Reason),
                {maps:put(ModName, {error, ErrMsg, erlang:monotonic_time(second)}, Mods),
                 maps:put(File, Mtime, Mtimes)}
        end
    end, {#{}, #{}}, Files).

recompile_and_reload(File, #{modules := Mods, reloads := Reloads,
                              errors := Errors, out_dir := OutDir} = State) ->
    ModName = detect_module(File),
    case winn:compile_file(File, OutDir) of
        {ok, _} ->
            code:purge(ModName),
            code:load_file(ModName),
            NewMods = maps:put(ModName, {ok, erlang:monotonic_time(second)}, Mods),
            WasError = case maps:get(ModName, Mods, undefined) of
                {error, _, _} -> true;
                _ -> false
            end,
            NewErrors = case WasError of true -> Errors - 1; false -> Errors end,
            State#{modules => NewMods, reloads => Reloads + 1, errors => NewErrors};
        {error, Reason} ->
            ErrMsg = format_error(Reason),
            NewMods = maps:put(ModName, {error, ErrMsg, erlang:monotonic_time(second)}, Mods),
            WasOk = case maps:get(ModName, Mods, undefined) of
                {ok, _} -> true;
                undefined -> true;
                _ -> false
            end,
            NewErrors = case WasOk of true -> Errors + 1; false -> Errors end,
            State#{modules => NewMods, errors => NewErrors}
    end.

detect_module(File) ->
    case file:read_file(File) of
        {ok, Bin} ->
            Source = binary_to_list(Bin),
            case re:run(Source, "^\\s*module\\s+([A-Z][a-zA-Z0-9_.]*)",
                        [{capture, [1], list}, multiline]) of
                {match, [ModStr]} ->
                    list_to_atom(string:lowercase(ModStr));
                nomatch ->
                    list_to_atom(filename:basename(File, ".winn"))
            end;
        _ ->
            list_to_atom(filename:basename(File, ".winn"))
    end.

format_error({file_read, _Path, Reason}) ->
    io_lib:format("~p", [Reason]);
format_error({Line, winn_parser, Msg}) ->
    io_lib:format("line ~B: ~s", [Line, Msg]);
format_error(Reason) when is_list(Reason) ->
    Reason;
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

count_errors(Mods) ->
    maps:fold(fun(_, {error, _, _}, Acc) -> Acc + 1;
                 (_, _, Acc) -> Acc end, 0, Mods).

%% ── App startup (mirrors winn_cli:start_project) ───────────────────────────

start_app(Files) ->
    add_dep_paths(),
    start_otp_apps(),
    case Files of
        [First | _] ->
            ModAtom = detect_module(First),
            case erlang:function_exported(ModAtom, main, 0) of
                true  -> spawn(fun() -> ModAtom:main() end);
                false ->
                    case erlang:function_exported(ModAtom, main, 1) of
                        true  -> spawn(fun() -> ModAtom:main([]) end);
                        false -> ok
                    end
            end;
        _ -> ok
    end.

add_dep_paths() ->
    Paths = filelib:wildcard("_build/default/lib/*/ebin")
         ++ filelib:wildcard("_build/prod/lib/*/ebin"),
    [code:add_patha(P) || P <- Paths].

start_otp_apps() ->
    Apps = [crypto, asn1, public_key, ssl, inets],
    lists:foreach(fun(App) ->
        application:ensure_all_started(App)
    end, Apps).

%% ── Dashboard rendering ─────────────────────────────────────────────────────

draw_dashboard(State) ->
    Output = format_dashboard(State),
    io:format("\e[H~ts", [Output]).

format_dashboard(#{modules := Mods, reloads := Reloads,
                    errors := Errors, start_time := StartTime}) ->
    Now = erlang:monotonic_time(second),
    Uptime = Now - StartTime,
    ModCount = maps:size(Mods),
    Width = 50,

    %% Header
    Title = " Winn Watch ",
    PadLen = Width - length(Title) - 2,
    Header = io_lib:format("\e[1m~ts~ts~ts~ts\e[0m~n",
        [[$\x{250C}, $\x{2500}], Title,
         lists:duplicate(max(0, PadLen), $\x{2500}), [$\x{2510}]]),

    %% Subtitle
    SubText = io_lib:format(" Watching src/ (~B module~s)", [ModCount, plural(ModCount)]),
    SubLine = pad_line(SubText, Width),

    %% Blank line
    BlankLine = pad_line("", Width),

    %% Module lines
    SortedMods = lists:sort(maps:to_list(Mods)),
    ModLines = lists:flatmap(fun({ModName, Status}) ->
        format_module_line(ModName, Status, Now, Width)
    end, SortedMods),

    %% Footer stats
    StatsText = io_lib:format(" Reloads: ~B  Errors: ~B  Uptime: ~s",
        [Reloads, Errors, format_uptime(Uptime)]),
    StatsLine = pad_line(StatsText, Width),

    %% Bottom border
    Bottom = io_lib:format("\e[1m~ts~ts~ts\e[0m~n",
        [[$\x{2514}], lists:duplicate(Width - 2, $\x{2500}), [$\x{2518}]]),

    lists:flatten([Header, SubLine, BlankLine | ModLines] ++ [BlankLine, StatsLine, Bottom]).

format_module_line(ModName, {ok, ReloadTime}, Now, Width) ->
    Elapsed = format_elapsed(Now - ReloadTime),
    ModStr = atom_to_list(ModName),
    PaddedName = pad_right(ModStr, 14),
    Text = io_lib:format(" \e[32m\x{2713}\e[0m ~ts reloaded ~ts", [PaddedName, Elapsed]),
    [pad_line_ansi(Text, Width)];
format_module_line(ModName, {error, ErrMsg, _Since}, _Now, Width) ->
    ModStr = atom_to_list(ModName),
    PaddedName = pad_right(ModStr, 14),
    Text = io_lib:format(" \e[31m\x{2717}\e[0m ~ts \e[31mcompile error\e[0m", [PaddedName]),
    ErrText = io_lib:format("   \x{2514} ~ts", [truncate(lists:flatten(ErrMsg), 35)]),
    [pad_line_ansi(Text, Width), pad_line_ansi(ErrText, Width)].

%% ── Formatting helpers ──────────────────────────────────────────────────────

format_elapsed(Secs) when Secs < 0 -> "just now";
format_elapsed(0) -> "just now";
format_elapsed(Secs) when Secs < 60 ->
    io_lib:format("~Bs ago", [Secs]);
format_elapsed(Secs) when Secs < 3600 ->
    io_lib:format("~Bm ~Bs ago", [Secs div 60, Secs rem 60]);
format_elapsed(Secs) ->
    io_lib:format("~Bh ~Bm ago", [Secs div 3600, (Secs rem 3600) div 60]).

format_uptime(Secs) when Secs < 60 ->
    io_lib:format("~Bs", [Secs]);
format_uptime(Secs) when Secs < 3600 ->
    io_lib:format("~Bm ~Bs", [Secs div 60, Secs rem 60]);
format_uptime(Secs) ->
    io_lib:format("~Bh ~Bm", [Secs div 3600, (Secs rem 3600) div 60]).

pad_line(Text, Width) ->
    Flat = lists:flatten(Text),
    Len = string:length(Flat),
    Pad = max(0, Width - 2 - Len),
    io_lib:format("\x{2502}~ts~ts\x{2502}~n", [Flat, lists:duplicate(Pad, $\s)]).

pad_line_ansi(Text, Width) ->
    %% ANSI escape codes don't count toward visible width
    Flat = lists:flatten(Text),
    VisLen = visible_length(Flat),
    Pad = max(0, Width - 2 - VisLen),
    io_lib:format("\x{2502}~ts~ts\x{2502}~n", [Flat, lists:duplicate(Pad, $\s)]).

visible_length(Str) ->
    %% Strip ANSI escape sequences to calculate visible width
    Re = "\e\\[[0-9;]*m",
    Stripped = re:replace(Str, Re, "", [global, unicode, {return, list}]),
    string:length(Stripped).

pad_right(Str, Width) ->
    Len = string:length(Str),
    case Len >= Width of
        true  -> Str;
        false -> Str ++ lists:duplicate(Width - Len, $\s)
    end.

truncate(Str, MaxLen) ->
    case string:length(Str) > MaxLen of
        true  -> string:slice(Str, 0, MaxLen - 3) ++ "...";
        false -> Str
    end.

plural(1) -> "";
plural(_) -> "s".

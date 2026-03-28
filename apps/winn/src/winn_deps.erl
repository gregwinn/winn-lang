%% winn_deps.erl
%% Dependency management for Winn projects.
%%
%% Reads and writes the {deps, [...]} section of rebar.config.
%% Delegates to rebar3 for actual fetching and compilation.

-module(winn_deps).
-export([list/0, add/2, remove/1, install/0]).
-export([read_deps_for_test/0]).  %% exported for tests

-define(CONFIG_FILE, "rebar.config").

%% ── Public API ──────────────────────────────────────────────────────────

%% List all dependencies from rebar.config.
list() ->
    case read_deps() of
        {ok, Deps} ->
            case Deps of
                [] ->
                    io:format("No dependencies.~n");
                _ ->
                    io:format("Dependencies:~n"),
                    lists:foreach(fun({Name, Vsn}) ->
                        io:format("  ~s ~s~n", [Name, Vsn])
                    end, Deps)
            end,
            ok;
        {error, Reason} ->
            io:format("Error reading rebar.config: ~p~n", [Reason]),
            {error, Reason}
    end.

%% Add a dependency to rebar.config and install it.
add(Name, Version) when is_list(Name), is_list(Version) ->
    NameAtom = list_to_atom(Name),
    case read_deps() of
        {ok, Deps} ->
            case lists:keyfind(NameAtom, 1, Deps) of
                {NameAtom, Version} ->
                    io:format("~s ~s is already installed.~n", [Name, Version]),
                    ok;
                {NameAtom, OldVsn} ->
                    NewDeps = lists:keyreplace(NameAtom, 1, Deps, {NameAtom, Version}),
                    case write_deps(NewDeps) of
                        ok ->
                            io:format("Updated ~s ~s → ~s~n", [Name, OldVsn, Version]),
                            install();
                        Err -> Err
                    end;
                false ->
                    NewDeps = Deps ++ [{NameAtom, Version}],
                    case write_deps(NewDeps) of
                        ok ->
                            io:format("Added ~s ~s~n", [Name, Version]),
                            install();
                        Err -> Err
                    end
            end;
        {error, Reason} ->
            io:format("Error reading rebar.config: ~p~n", [Reason]),
            {error, Reason}
    end.

%% Remove a dependency from rebar.config.
remove(Name) when is_list(Name) ->
    NameAtom = list_to_atom(Name),
    case read_deps() of
        {ok, Deps} ->
            case lists:keyfind(NameAtom, 1, Deps) of
                false ->
                    io:format("~s is not a dependency.~n", [Name]),
                    ok;
                _ ->
                    NewDeps = lists:keydelete(NameAtom, 1, Deps),
                    case write_deps(NewDeps) of
                        ok ->
                            io:format("Removed ~s~n", [Name]),
                            ok;
                        Err -> Err
                    end
            end;
        {error, Reason} ->
            io:format("Error reading rebar.config: ~p~n", [Reason]),
            {error, Reason}
    end.

%% Install all dependencies (fetch + compile).
install() ->
    io:format("Fetching dependencies...~n"),
    case run_rebar3("get-deps") of
        0 ->
            io:format("Compiling dependencies...~n"),
            case run_rebar3("compile") of
                0 ->
                    io:format("Done.~n"),
                    ok;
                Code ->
                    io:format("Compile failed (exit ~p).~n", [Code]),
                    {error, compile_failed}
            end;
        Code ->
            io:format("Fetch failed (exit ~p).~n", [Code]),
            {error, fetch_failed}
    end.

%% ── rebar.config parsing ────────────────────────────────────────────────

read_deps_for_test() -> read_deps().

read_deps() ->
    case file:consult(?CONFIG_FILE) of
        {ok, Terms} ->
            Deps = proplists:get_value(deps, Terms, []),
            Normalized = [normalize_dep(D) || D <- Deps],
            {ok, Normalized};
        {error, enoent} ->
            {error, no_rebar_config};
        {error, Reason} ->
            {error, Reason}
    end.

normalize_dep({Name, Vsn}) when is_atom(Name), is_list(Vsn) ->
    {Name, Vsn};
normalize_dep({Name, Vsn}) when is_atom(Name), is_binary(Vsn) ->
    {Name, binary_to_list(Vsn)};
normalize_dep(Other) ->
    Other.

write_deps(Deps) ->
    case file:consult(?CONFIG_FILE) of
        {ok, Terms} ->
            NewTerms = lists:keystore(deps, 1, Terms, {deps, format_deps(Deps)}),
            Content = format_rebar_config(NewTerms),
            file:write_file(?CONFIG_FILE, Content);
        {error, Reason} ->
            {error, Reason}
    end.

format_deps(Deps) ->
    [{Name, Vsn} || {Name, Vsn} <- Deps].

%% Format rebar.config terms back to readable Erlang term format.
format_rebar_config(Terms) ->
    Lines = lists:map(fun(Term) -> format_term(Term) end, Terms),
    iolist_to_binary(lists:join("\n", Lines)).

format_term({deps, Deps}) ->
    DepLines = [io_lib:format("    {~s, \"~s\"}", [Name, Vsn]) || {Name, Vsn} <- Deps],
    ["{deps, [\n", lists:join(",\n", DepLines), "\n]}.\n"];
format_term(Term) ->
    [io_lib:format("~p.", [Term]), "\n"].

%% ── Shell command execution ─────────────────────────────────────────────

run_rebar3(Command) ->
    %% Find rebar3 — check PATH, then common locations
    Rebar3 = find_rebar3(),
    Port = open_port({spawn, Rebar3 ++ " " ++ Command},
                     [exit_status, stderr_to_stdout, {line, 1024}]),
    collect_port_output(Port).

find_rebar3() ->
    case os:find_executable("rebar3") of
        false -> "rebar3";  %% hope for the best
        Path  -> Path
    end.

collect_port_output(Port) ->
    receive
        {Port, {data, {eol, Line}}} ->
            io:format("  ~s~n", [Line]),
            collect_port_output(Port);
        {Port, {data, {noeol, Line}}} ->
            io:format("  ~s", [Line]),
            collect_port_output(Port);
        {Port, {exit_status, Status}} ->
            Status
    after 120000 ->
        io:format("Timeout waiting for rebar3.~n"),
        1
    end.

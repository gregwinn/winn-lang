%% winn_cli.erl
%% Escript entry point for the Winn CLI.

-module(winn_cli).
-export([main/1, parse_args/1, scaffold/1]).

%% ── Entry point ───────────────────────────────────────────────────────────

main(Args) ->
    %% Enable color output when running in a terminal.
    winn_errors:set_color(is_tty()),
    case parse_args(Args) of
        {new, Name} ->
            case scaffold(Name) of
                ok ->
                    io:format("Created project ~s~n", [Name]),
                    halt(0);
                {error, Reason} ->
                    io:format("Error creating project: ~p~n", [Reason]),
                    halt(1)
            end;

        {compile, []} ->
            Files = filelib:wildcard("*.winn"),
            case Files of
                [] ->
                    io:format("No .winn files found in current directory~n"),
                    halt(0);
                _ ->
                    ok = ensure_dir("ebin"),
                    Results = [compile_one(F, "ebin") || F <- Files],
                    Errors = [E || {error, E} <- Results],
                    case Errors of
                        [] -> halt(0);
                        _  -> halt(1)
                    end
            end;

        {compile, [File]} ->
            ok = ensure_dir("ebin"),
            case compile_one(File, "ebin") of
                {ok, _} -> halt(0);
                {error, _} -> halt(1)
            end;

        {run, File, _ExtraArgs} ->
            TmpDir = os:getenv("TMPDIR", "/tmp") ++
                     "/winn_run_" ++
                     integer_to_list(erlang:unique_integer([positive])),
            ok = ensure_dir(TmpDir),
            case compile_one(File, TmpDir) of
                {ok, _BeamFiles} ->
                    true = code:add_path(TmpDir),
                    BaseName = filename:basename(File, ".winn"),
                    ModAtom = list_to_atom(BaseName),
                    Result =
                        try
                            case erlang:function_exported(ModAtom, main, 0) of
                                true ->
                                    ModAtom:main();
                                false ->
                                    ModAtom:main([])
                            end,
                            ok
                        catch
                            error:undef ->
                                io:format("Error: ~s has no main/0 or main/1 function~n",
                                          [BaseName]),
                                {error, undef};
                            Class:Reason ->
                                io:format("Error running ~s: ~p:~p~n",
                                          [BaseName, Class, Reason]),
                                {error, {Class, Reason}}
                        end,
                    cleanup_dir(TmpDir),
                    case Result of
                        ok -> halt(0);
                        {error, _} -> halt(1)
                    end;
                {error, _} ->
                    cleanup_dir(TmpDir),
                    halt(1)
            end;

        help ->
            print_usage(),
            halt(0);

        unknown ->
            io:format("Error: unknown command. Run `winn help` for usage.~n"),
            halt(1)
    end.

%% ── Argument parsing ──────────────────────────────────────────────────────

parse_args(["new", Name])        -> {new, Name};
parse_args(["compile"])          -> {compile, []};
parse_args(["compile", File])    -> {compile, [File]};
parse_args(["run", File | Args]) -> {run, File, Args};
parse_args(["help" | _])         -> help;
parse_args([])                   -> help;
parse_args(_)                    -> unknown.

%% ── Scaffold ──────────────────────────────────────────────────────────────

scaffold(AppName) ->
    BaseName = filename:basename(AppName),
    SrcDir = AppName ++ "/src",
    WinnFile = SrcDir ++ "/" ++ BaseName ++ ".winn",
    RebarFile = AppName ++ "/rebar.config",
    GitignoreFile = AppName ++ "/.gitignore",
    try
        ok = file:make_dir(AppName),
        ok = file:make_dir(SrcDir),
        ok = file:write_file(WinnFile, starter_winn(AppName)),
        ok = file:write_file(RebarFile, starter_rebar(AppName)),
        ok = file:write_file(GitignoreFile, gitignore_content()),
        ok
    catch
        error:{badmatch, {error, Reason}} ->
            {error, Reason};
        _Class:Reason ->
            {error, Reason}
    end.

starter_winn(AppName) ->
    ModName = to_pascal_case(AppName),
    io_lib:format(
        "module ~s\n  def main()\n    IO.puts(\"Hello from ~s!\")\n  end\nend\n",
        [ModName, AppName]
    ).

starter_rebar(AppName) ->
    io_lib:format(
        "{erl_opts, [debug_info]}.\n\n{deps, []}.\n\n"
        "{escript_main_app, ~s}.\n"
        "{escript_name, ~s}.\n",
        [AppName, AppName]
    ).

gitignore_content() ->
    "_build/\nebin/\n*.beam\n".

%% ── Internal helpers ──────────────────────────────────────────────────────

compile_one(File, OutDir) ->
    %% Errors are already formatted and printed by winn:compile_file.
    winn:compile_file(File, OutDir).

ensure_dir(Dir) ->
    case file:make_dir(Dir) of
        ok              -> ok;
        {error, eexist} -> ok;
        {error, Reason} -> {error, Reason}
    end.

cleanup_dir(Dir) ->
    Beams = filelib:wildcard(Dir ++ "/*.beam"),
    [file:delete(B) || B <- Beams],
    file:del_dir(Dir).

%% Convert snake_case or lowercase name to PascalCase.
%% "hello_world" -> "HelloWorld", "my_app" -> "MyApp", "hello" -> "Hello"
to_pascal_case(Name) ->
    Parts = string:split(Name, "_", all),
    lists:flatten([capitalize(P) || P <- Parts]).

capitalize([]) -> [];
capitalize([C | Rest]) when C >= $a, C =< $z -> [C - 32 | Rest];
capitalize(S) -> S.

is_tty() ->
    case io:columns() of
        {ok, _} -> true;
        _       -> false
    end.

print_usage() ->
    io:format(
        "Winn - a compiled language on the BEAM~n~n"
        "Usage:~n"
        "  winn new <name>       Create a new Winn project~n"
        "  winn compile          Compile all *.winn files in current directory~n"
        "  winn compile <file>   Compile a single .winn file~n"
        "  winn run <file>       Compile and run a .winn file~n"
        "  winn help             Show this help text~n"
    ).

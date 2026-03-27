%% winn_cli.erl
%% Escript entry point for the Winn CLI.

-module(winn_cli).
-export([main/1, parse_args/1, scaffold/1]).

%% ── Entry point ───────────────────────────────────────────────────────────

main(Args) ->
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
            compile_all();

        {compile, [File]} ->
            ok = ensure_dir("ebin"),
            case compile_one(File, "ebin") of
                {ok, _} -> halt(0);
                {error, _} -> halt(1)
            end;

        {run, File, _ExtraArgs} ->
            run_file(File);

        {start, ExtraArgs} ->
            start_project(ExtraArgs);

        version ->
            print_version(),
            halt(0);

        help ->
            print_usage(),
            halt(0);

        unknown ->
            io:format("Error: unknown command. Run `winn help` for usage.~n"),
            halt(1)
    end.

%% ── Argument parsing ──────────────────────────────────────────────────────

parse_args(["new", Name])          -> {new, Name};
parse_args(["compile"])            -> {compile, []};
parse_args(["compile", File])      -> {compile, [File]};
parse_args(["run", File | Args])   -> {run, File, Args};
parse_args(["start" | Args])       -> {start, Args};
parse_args(["version" | _])        -> version;
parse_args(["-v" | _])             -> version;
parse_args(["--version" | _])      -> version;
parse_args(["help" | _])           -> help;
parse_args([])                     -> help;
parse_args(_)                      -> unknown.

%% ── Compile all ─────────────────────────────────────────────────────────

compile_all() ->
    %% Look for .winn files in src/ first, then current dir.
    SrcFiles = filelib:wildcard("src/*.winn"),
    CurFiles = filelib:wildcard("*.winn"),
    Files = case SrcFiles of
        [] -> CurFiles;
        _  -> SrcFiles
    end,
    case Files of
        [] ->
            io:format("No .winn files found in src/ or current directory.~n"),
            halt(0);
        _ ->
            ok = ensure_dir("ebin"),
            Results = [compile_one(F, "ebin") || F <- Files],
            Errors = [E || {error, E} <- Results],
            case Errors of
                [] ->
                    io:format("Compiled ~B file(s) to ebin/~n", [length(Files)]),
                    halt(0);
                _ ->
                    halt(1)
            end
    end.

%% ── Run a single file ──────────────────────────────────────────────────

run_file(File) ->
    TmpDir = tmp_dir(),
    ok = ensure_dir(TmpDir),
    case compile_one(File, TmpDir) of
        {ok, _BeamFiles} ->
            true = code:add_path(TmpDir),
            ModAtom = detect_module_name(File),
            Result = call_main(ModAtom),
            cleanup_dir(TmpDir),
            case Result of
                ok -> halt(0);
                {error, _} -> halt(1)
            end;
        {error, _} ->
            cleanup_dir(TmpDir),
            halt(1)
    end.

%% ── Start a project (compile all, load deps, run, keep alive) ──────────

start_project(Args) ->
    %% Compile all .winn files.
    SrcFiles = filelib:wildcard("src/*.winn"),
    CurFiles = filelib:wildcard("*.winn"),
    Files = case SrcFiles of
        [] -> CurFiles;
        _  -> SrcFiles
    end,
    case Files of
        [] ->
            io:format("No .winn files found in src/ or current directory.~n"),
            halt(1);
        _ ->
            ok = ensure_dir("ebin"),
            Results = [compile_one(F, "ebin") || F <- Files],
            Errors = [E || {error, E} <- Results],
            case Errors of
                [] -> ok;
                _  -> halt(1)
            end
    end,

    %% Add ebin and any dependency paths to the code path.
    true = code:add_path("ebin"),
    add_dep_paths(),

    %% Start required OTP applications.
    start_applications(),

    %% Find the main module: first arg, or detect from first .winn file.
    ModAtom = case Args of
        [ModStr | _] -> list_to_atom(ModStr);
        []           -> detect_module_name(hd(Files))
    end,

    io:format("Starting ~s...~n", [ModAtom]),

    %% Call main — if it starts a server, we keep the VM alive.
    case call_main(ModAtom) of
        ok ->
            %% Keep the VM running (for servers, GenServers, etc.)
            %% Block forever so the BEAM doesn't exit.
            receive
                stop -> halt(0)
            end;
        {error, _} ->
            halt(1)
    end.

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
    winn:compile_file(File, OutDir).

%% Detect the module name by reading the first `module Name` line from the source.
detect_module_name(File) ->
    case file:read_file(File) of
        {ok, Binary} ->
            Source = binary_to_list(Binary),
            case re:run(Source, "^\\s*module\\s+([A-Z][a-zA-Z0-9_.]*)",
                        [{capture, [1], list}, multiline]) of
                {match, [ModStr]} ->
                    %% Module names compile to lowercase: HelloWorld -> helloworld
                    list_to_atom(string:lowercase(ModStr));
                nomatch ->
                    %% Fallback: derive from filename
                    list_to_atom(filename:basename(File, ".winn"))
            end;
        {error, _} ->
            list_to_atom(filename:basename(File, ".winn"))
    end.

call_main(ModAtom) ->
    %% Ensure the module is loaded so function_exported works.
    code:purge(ModAtom),
    code:load_file(ModAtom),
    try
        case erlang:function_exported(ModAtom, main, 0) of
            true  -> ModAtom:main();
            false ->
                case erlang:function_exported(ModAtom, main, 1) of
                    true  -> ModAtom:main([]);
                    false ->
                        io:format("Error: ~s has no main/0 or main/1 function.~n", [ModAtom]),
                        throw(no_main)
                end
        end,
        ok
    catch
        throw:no_main ->
            {error, no_main};
        error:undef:Stack ->
            case Stack of
                [{ModAtom, main, _, _} | _] ->
                    io:format("Error: ~s:main is not exported.~n", [ModAtom]);
                _ ->
                    io:format("Error: undefined function call in ~s.~n", [ModAtom]),
                    io:format("  ~p~n", [hd(Stack)])
            end,
            {error, undef};
        Class:Reason:Stack ->
            io:format("Error running ~s:~n  ~p:~p~n", [ModAtom, Class, Reason]),
            io:format("  ~p~n", [hd(Stack)]),
            {error, {Class, Reason}}
    end.

%% Add _build dependency paths to the code path so compiled Winn modules
%% can call into hackney, cowboy, jsone, etc.
add_dep_paths() ->
    Patterns = [
        "_build/default/lib/*/ebin",
        "_build/prod/lib/*/ebin"
    ],
    Paths = lists:flatmap(fun filelib:wildcard/1, Patterns),
    [code:add_path(P) || P <- Paths],
    ok.

%% Start common OTP applications needed by Winn runtime modules.
start_applications() ->
    Apps = [crypto, asn1, public_key, ssl, inets],
    [application:ensure_all_started(A) || A <- Apps],
    %% Try to start optional deps (won't fail if not present).
    _ = application:ensure_all_started(cowboy),
    _ = application:ensure_all_started(hackney),
    _ = application:ensure_all_started(gun),
    ok.

tmp_dir() ->
    os:getenv("TMPDIR", "/tmp") ++
    "/winn_run_" ++
    integer_to_list(erlang:unique_integer([positive])).

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

get_version() ->
    case application:get_key(winn, vsn) of
        {ok, Vsn} -> Vsn;
        _         -> "0.2.0"
    end.

print_version() ->
    io:format("winn ~s~n", [get_version()]).

print_usage() ->
    io:format(
        "Winn ~s - a compiled language on the BEAM~n~n"
        "Usage:~n"
        "  winn new <name>         Create a new Winn project~n"
        "  winn compile            Compile all .winn files (src/ or current dir)~n"
        "  winn compile <file>     Compile a single .winn file~n"
        "  winn run <file>         Compile and run a single .winn file~n"
        "  winn start              Compile project and start (keeps VM alive)~n"
        "  winn start <module>     Start with a specific module~n"
        "  winn version            Show version~n"
        "  winn help               Show this help text~n",
        [get_version()]
    ).

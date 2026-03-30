%% winn_cli.erl
%% Escript entry point for the Winn CLI.

-module(winn_cli).
-export([main/1, parse_args/1, scaffold/1, task_name_to_module/1]).

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

        console ->
            winn_repl:start(),
            halt(0);

        {test, TestArgs} ->
            run_tests(TestArgs);

        {docs, DocsArgs} ->
            run_docs(DocsArgs);

        {watch, WatchArgs} ->
            Opts = #{start => lists:member("--start", WatchArgs)},
            winn_watch:start(Opts);

        {task, TaskArgs} ->
            run_task(TaskArgs);

        {deps, Sub} ->
            Result = run_deps(Sub),
            case Result of
                ok -> halt(0);
                {error, _} -> halt(1)
            end;

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
parse_args(["console" | _])        -> console;
parse_args(["test"])                -> {test, []};
parse_args(["test" | Args])        -> {test, Args};
parse_args(["docs"])                -> {docs, []};
parse_args(["docs" | Args])        -> {docs, Args};
parse_args(["watch" | Args])       -> {watch, Args};
parse_args(["task" | Args])        -> {task, Args};
parse_args(["deps" | Sub])         -> {deps, Sub};
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
    case filelib:ensure_path(Dir) of
        ok              -> ok;
        {error, Reason} -> {error, Reason}
    end.

cleanup_dir(Dir) ->
    Beams = filelib:wildcard(Dir ++ "/*.beam"),
    [file:delete(B) || B <- Beams],
    file:del_dir(Dir).

%% ── Test runner ─────────────────────────────────────────────────────────

run_tests(Args) ->
    Files = find_test_files(Args),
    case Files of
        [] ->
            io:format("No test files found.~n"),
            halt(1);
        _ ->
            TmpDir = "_build/test",
            ok = ensure_dir(TmpDir),
            {Compiled, Errors} = compile_test_files(Files, TmpDir),
            case Errors of
                [] -> ok;
                _ ->
                    io:format("~B file(s) failed to compile.~n", [length(Errors)]),
                    halt(1)
            end,
            Modules = load_test_beams(TmpDir, Compiled),
            case winn_test:run_tests(Modules) of
                ok    -> halt(0);
                error -> halt(1)
            end
    end.

find_test_files([]) ->
    %% Find all .winn files in test/ directory
    case filelib:is_dir("test") of
        true  -> filelib:wildcard("test/*.winn");
        false -> []
    end;
find_test_files(Paths) ->
    %% Specific files passed as arguments
    lists:filter(fun filelib:is_file/1, Paths).

compile_test_files(Files, OutDir) ->
    %% Also compile src/ first so test modules can call project modules
    SrcFiles = case filelib:is_dir("src") of
        true  -> filelib:wildcard("src/*.winn");
        false -> []
    end,
    SrcDir = "_build/test/src",
    ok = ensure_dir(SrcDir),
    lists:foreach(fun(F) ->
        case winn:compile_file(F, SrcDir) of
            {ok, _} -> ok;
            _ -> ok
        end
    end, SrcFiles),
    %% Add src beam dir to code path
    code:add_patha(SrcDir),
    %% Compile test files
    lists:foldl(fun(File, {Ok, Err}) ->
        case winn:compile_file(File, OutDir) of
            {ok, _} -> {[File | Ok], Err};
            {error, Reason} ->
                io:format("Error compiling ~s: ~p~n", [File, Reason]),
                {Ok, [File | Err]}
        end
    end, {[], []}, Files).

load_test_beams(Dir, _Compiled) ->
    code:add_patha(Dir),
    Beams = filelib:wildcard(Dir ++ "/*.beam"),
    lists:filtermap(fun(BeamPath) ->
        ModStr = filename:basename(BeamPath, ".beam"),
        Mod = list_to_atom(ModStr),
        code:purge(Mod),
        case code:load_file(Mod) of
            {module, Mod} -> {true, Mod};
            _ -> false
        end
    end, Beams).

%% ── Task runner ─────────────────────────────────────────────────────────

run_task([]) ->
    io:format("Usage: winn task <name> [args...]~n~n"
              "Available tasks are discovered from tasks/*.winn and src/*.winn~n"
              "modules that use Winn.Task and define a run/1 function.~n~n"
              "Task names use colons for namespacing (like Rails):~n"
              "  winn task db:migrate    => module Tasks.Db.Migrate~n"
              "  winn task db:seed       => module Tasks.Db.Seed~n"
              "  winn task routes        => module Tasks.Routes~n"),
    halt(0);
run_task([TaskName | Args]) ->
    %% Compile all source files
    OutDir = "_build/tasks",
    ok = filelib:ensure_path(OutDir),
    SrcFiles = filelib:wildcard("src/*.winn") ++ filelib:wildcard("tasks/*.winn"),
    case SrcFiles of
        [] ->
            io:format("No .winn files found.~n"),
            halt(1);
        _ ->
            lists:foreach(fun(F) ->
                case winn:compile_file(F, OutDir) of
                    {ok, _} -> ok;
                    {error, _} -> ok
                end
            end, SrcFiles),
            code:add_patha(OutDir),

            %% Map task name to module atom
            %% db.migrate -> tasks.db.migrate (try with tasks. prefix first)
            %% If not found, try just the dotted name lowercased
            ModAtom = task_name_to_module(TaskName),
            case code:ensure_loaded(ModAtom) of
                {module, ModAtom} ->
                    case erlang:function_exported(ModAtom, run, 1) of
                        true ->
                            try
                                ModAtom:run(Args),
                                halt(0)
                            catch
                                Class:Reason:Stack ->
                                    io:format("Task ~s failed: ~p:~p~n~p~n",
                                              [TaskName, Class, Reason, Stack]),
                                    halt(1)
                            end;
                        false ->
                            io:format("Error: module ~s does not export run/1~n", [ModAtom]),
                            halt(1)
                    end;
                _ ->
                    %% Try without tasks. prefix (convert colons to dots)
                    Dotted = lists:flatten(string:replace(TaskName, ":", ".", all)),
                    SimpleAtom = list_to_atom(string:lowercase(Dotted)),
                    case code:ensure_loaded(SimpleAtom) of
                        {module, SimpleAtom} ->
                            case erlang:function_exported(SimpleAtom, run, 1) of
                                true ->
                                    try
                                        SimpleAtom:run(Args),
                                        halt(0)
                                    catch
                                        Class:Reason:Stack ->
                                            io:format("Task ~s failed: ~p:~p~n~p~n",
                                                      [TaskName, Class, Reason, Stack]),
                                            halt(1)
                                    end;
                                false ->
                                    io:format("Error: task ~s not found~n", [TaskName]),
                                    halt(1)
                            end;
                        _ ->
                            io:format("Error: task ~s not found~n~n"
                                      "Make sure the task module exists in tasks/ or src/~n"
                                      "and uses Winn.Task with a run/1 function.~n",
                                      [TaskName]),
                            halt(1)
                    end
            end
    end.

task_name_to_module(Name) ->
    %% "db:migrate" -> "tasks.db.migrate" -> atom (Rails-style colon syntax)
    Dotted = string:replace(Name, ":", ".", all),
    list_to_atom("tasks." ++ string:lowercase(lists:flatten(Dotted))).

%% ── Docs generator ──────────────────────────────────────────────────────

run_docs(Args) ->
    Files = find_doc_files(Args),
    case Files of
        [] ->
            io:format("No .winn files found.~n"),
            halt(1);
        _ ->
            OutDir = "doc/api",
            case winn_docs:generate(Files, OutDir) of
                ok    -> halt(0);
                {error, _} -> halt(1)
            end
    end.

find_doc_files([]) ->
    case filelib:is_dir("src") of
        true  -> filelib:wildcard("src/*.winn");
        false -> filelib:wildcard("*.winn")
    end;
find_doc_files(Paths) ->
    lists:filter(fun filelib:is_file/1, Paths).

%% ── Deps subcommand ─────────────────────────────────────────────────────

run_deps(["list"])              -> winn_deps:list();
run_deps(["add", Name, Vsn])   -> winn_deps:add(Name, Vsn);
run_deps(["remove", Name])     -> winn_deps:remove(Name);
run_deps(["install"])           -> winn_deps:install();
run_deps([]) ->
    io:format("Usage:~n"
              "  winn deps list              List dependencies~n"
              "  winn deps add <name> <vsn>  Add a dependency~n"
              "  winn deps remove <name>     Remove a dependency~n"
              "  winn deps install           Fetch and compile deps~n"),
    ok;
run_deps(_) ->
    io:format("Unknown deps command. Run `winn deps` for usage.~n"),
    {error, unknown}.

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
        _         -> "0.4.0"
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
        "  winn test               Run all tests in test/~n"
        "  winn test <file>        Run a specific test file~n"
        "  winn docs               Generate API docs with dependency graph~n"
        "  winn docs <file>        Generate docs for a single file~n"
        "  winn watch              Watch files and hot-reload with live dashboard~n"
        "  winn watch --start      Watch + start the app~n"
        "  winn task <name>        Run a project task (e.g., winn task db:migrate)~n"
        "  winn deps               Manage dependencies~n"
        "  winn console            Interactive console~n"
        "  winn version            Show version~n"
        "  winn help               Show this help text~n",
        [get_version()]
    ).

%% winn_cli.erl
%% Escript entry point for the Winn CLI.

-module(winn_cli).
-export([main/1, parse_args/1, scaffold/1, task_name_to_module/1, generate_dockerfile/0]).

%% ── Entry point ───────────────────────────────────────────────────────────

main(Args) ->
    winn_errors:set_color(is_tty()),
    case parse_args(Args) of
        {new, Name, Opts} ->
            case scaffold(Name, Opts) of
                ok ->
                    io:format("Created project ~s~n~n", [Name]),
                    io:format("  cd ~s~n  winn run src/~s.winn~n~n", [Name, filename:basename(Name)]),
                    halt(0);
                {error, Reason} ->
                    io:format("Error creating project: ~p~n", [Reason]),
                    halt(1)
            end;

        {new_usage} ->
            io:format("Usage: winn new <name> [--api | --minimal]~n"),
            halt(1);

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

        {create, CreateArgs} ->
            run_create(CreateArgs);

        {pkg_add, [Name]} ->
            winn_package:add(Name),
            halt(0);
        {pkg_add, _} ->
            io:format("Usage: winn add <package-name>~n"),
            halt(1);
        {pkg_remove, [Name]} ->
            winn_package:remove(Name),
            halt(0);
        {pkg_remove, _} ->
            io:format("Usage: winn remove <package-name>~n"),
            halt(1);
        pkg_list ->
            winn_package:list(),
            halt(0);
        pkg_install ->
            winn_package:install(),
            halt(0);

        {task, TaskArgs} ->
            run_task(TaskArgs);

        {bench, BenchArgs} ->
            run_bench(BenchArgs);

        {metrics, MetricsArgs} ->
            winn_metrics_dashboard:start(#{args => MetricsArgs});

        {release, ReleaseArgs} ->
            run_release(ReleaseArgs);

        {migrate, MigrateArgs} ->
            run_migrate(MigrateArgs);

        {rollback, RollbackArgs} ->
            run_rollback(RollbackArgs);

        {fmt, FmtArgs} ->
            run_fmt(FmtArgs);

        {fmt_check, FmtArgs} ->
            run_fmt_check(FmtArgs);

        {lint, LintArgs} ->
            run_lint(LintArgs);

        {deps, Sub} ->
            Result = run_deps(Sub),
            case Result of
                ok -> halt(0);
                {error, _} -> halt(1)
            end;

        lsp ->
            winn_lsp:start();

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

parse_args(["new", Name | Flags])   -> {new, Name, parse_new_flags(Flags)};
parse_args(["new"])                 -> {new_usage};
parse_args(["compile"])            -> {compile, []};
parse_args(["compile", File])      -> {compile, [File]};
parse_args(["c"])                  -> {compile, []};
parse_args(["c", File])            -> {compile, [File]};
parse_args(["run", File | Args])   -> {run, File, Args};
parse_args(["r", File | Args])     -> {run, File, Args};
parse_args(["start" | Args])       -> {start, Args};
parse_args(["s" | Args])           -> {start, Args};
parse_args(["console" | _])        -> console;
parse_args(["con" | _])            -> console;
parse_args(["test"])                -> {test, []};
parse_args(["test" | Args])        -> {test, Args};
parse_args(["t"])                  -> {test, []};
parse_args(["t" | Args])          -> {test, Args};
parse_args(["docs"])                -> {docs, []};
parse_args(["docs" | Args])        -> {docs, Args};
parse_args(["d"])                  -> {docs, []};
parse_args(["d" | Args])          -> {docs, Args};
parse_args(["watch" | Args])       -> {watch, Args};
parse_args(["w" | Args])          -> {watch, Args};
parse_args(["task" | Args])        -> {task, Args};
parse_args(["create" | Args])      -> {create, Args};
parse_args(["add" | Args])         -> {pkg_add, Args};
parse_args(["remove" | Args])      -> {pkg_remove, Args};
parse_args(["packages" | _])       -> pkg_list;
parse_args(["install" | _])        -> pkg_install;
parse_args(["g" | Args])           -> {create, Args};
parse_args(["bench" | Args])       -> {bench, Args};
parse_args(["metrics" | Args])     -> {metrics, Args};
parse_args(["release" | Args])     -> {release, Args};
parse_args(["migrate" | Args])     -> {migrate, Args};
parse_args(["rollback" | Args])    -> {rollback, Args};
parse_args(["fmt"])                 -> {fmt, []};
parse_args(["fmt" | Args])         ->
    case lists:member("--check", Args) of
        true  -> {fmt_check, Args -- ["--check"]};
        false -> {fmt, Args}
    end;
parse_args(["f"])                   -> {fmt, []};
parse_args(["f" | Args])           ->
    case lists:member("--check", Args) of
        true  -> {fmt_check, Args -- ["--check"]};
        false -> {fmt, Args}
    end;
parse_args(["lint"])                 -> {lint, []};
parse_args(["lint" | Args])         -> {lint, Args};
parse_args(["l"])                   -> {lint, []};
parse_args(["l" | Args])           -> {lint, Args};
parse_args(["lsp" | _])            -> lsp;
parse_args(["deps" | Sub])         -> {deps, Sub};
parse_args(["version" | _])        -> version;
parse_args(["-v" | _])             -> version;
parse_args(["--version" | _])      -> version;
parse_args(["help" | _])           -> help;
parse_args(["-h" | _])            -> help;
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

parse_new_flags(Flags) ->
    lists:foldl(fun("--api", Acc)     -> Acc#{mode => api};
                   ("--minimal", Acc) -> Acc#{mode => minimal};
                   (_, Acc)           -> Acc
                end, #{mode => default}, Flags).

scaffold(AppName, Opts) ->
    BaseName = filename:basename(AppName),
    Mode = maps:get(mode, Opts, default),
    try
        ok = file:make_dir(AppName),
        ok = filelib:ensure_path(AppName ++ "/src"),
        ok = file:write_file(AppName ++ "/rebar.config", scaffold_rebar(AppName)),
        ok = file:write_file(AppName ++ "/.gitignore", scaffold_gitignore()),
        ok = file:write_file(AppName ++ "/package.json", scaffold_package_json(BaseName)),
        case Mode of
            minimal ->
                ok = file:write_file(AppName ++ "/src/" ++ BaseName ++ ".winn",
                                     scaffold_winn_minimal(AppName));
            api ->
                ok = filelib:ensure_path(AppName ++ "/src/models"),
                ok = filelib:ensure_path(AppName ++ "/src/controllers"),
                ok = filelib:ensure_path(AppName ++ "/src/tasks"),
                ok = filelib:ensure_path(AppName ++ "/test"),
                ok = filelib:ensure_path(AppName ++ "/db/migrations"),
                ok = filelib:ensure_path(AppName ++ "/config"),
                ok = file:write_file(AppName ++ "/src/" ++ BaseName ++ ".winn",
                                     scaffold_winn_api(AppName)),
                ok = file:write_file(AppName ++ "/src/controllers/health_controller.winn",
                                     scaffold_health_controller(AppName)),
                ok = file:write_file(AppName ++ "/test/" ++ BaseName ++ "_test.winn",
                                     scaffold_test(AppName)),
                ok = file:write_file(AppName ++ "/config/config.winn",
                                     scaffold_config(AppName)),
                ok = file:write_file(AppName ++ "/db/seeds.winn", scaffold_seeds()),
                ok = file:write_file(AppName ++ "/.env.example", scaffold_env_example()),
                ok = file:write_file(AppName ++ "/README.md", scaffold_readme(AppName));
            default ->
                ok = filelib:ensure_path(AppName ++ "/src/models"),
                ok = filelib:ensure_path(AppName ++ "/src/controllers"),
                ok = filelib:ensure_path(AppName ++ "/src/tasks"),
                ok = filelib:ensure_path(AppName ++ "/test"),
                ok = filelib:ensure_path(AppName ++ "/db/migrations"),
                ok = filelib:ensure_path(AppName ++ "/config"),
                ok = file:write_file(AppName ++ "/src/" ++ BaseName ++ ".winn",
                                     scaffold_winn_default(AppName)),
                ok = file:write_file(AppName ++ "/test/" ++ BaseName ++ "_test.winn",
                                     scaffold_test(AppName)),
                ok = file:write_file(AppName ++ "/config/config.winn",
                                     scaffold_config(AppName)),
                ok = file:write_file(AppName ++ "/db/seeds.winn", scaffold_seeds()),
                ok = file:write_file(AppName ++ "/.env.example", scaffold_env_example()),
                ok = file:write_file(AppName ++ "/README.md", scaffold_readme(AppName))
        end,
        ok
    catch
        error:{badmatch, {error, Reason}} ->
            {error, Reason};
        _Class:Reason ->
            {error, Reason}
    end.

%% Keep backward-compatible scaffold/1
scaffold(AppName) -> scaffold(AppName, #{mode => default}).

%% ── Scaffold templates ──────────────────────────────────────────────────

scaffold_winn_minimal(AppName) ->
    Mod = to_pascal_case(AppName),
    io_lib:format(
        "module ~s\n"
        "  def main()\n"
        "    IO.puts(\"Hello from ~s!\")\n"
        "  end\n"
        "end\n", [Mod, AppName]).

scaffold_winn_default(AppName) ->
    Mod = to_pascal_case(AppName),
    io_lib:format(
        "module ~s\n"
        "  def main()\n"
        "    IO.puts(\"Hello from ~s!\")\n"
        "  end\n"
        "end\n", [Mod, AppName]).

scaffold_winn_api(AppName) ->
    Mod = to_pascal_case(AppName),
    io_lib:format(
        "module ~s\n"
        "  use Winn.Router\n"
        "\n"
        "  def routes()\n"
        "    [{:get, \"/api/health\", :health}]\n"
        "  end\n"
        "\n"
        "  def health(conn)\n"
        "    Server.json(conn, %{status: \"ok\"})\n"
        "  end\n"
        "\n"
        "  def main()\n"
        "    Server.start(~s, 4000)\n"
        "    IO.puts(\"~s running on port 4000\")\n"
        "  end\n"
        "end\n", [Mod, Mod, AppName]).

scaffold_health_controller(AppName) ->
    Mod = to_pascal_case(AppName),
    io_lib:format(
        "module ~s.HealthController\n"
        "  def check(conn)\n"
        "    Server.json(conn, %{status: \"ok\", version: \"0.1.0\"})\n"
        "  end\n"
        "end\n", [Mod]).

scaffold_test(AppName) ->
    Mod = to_pascal_case(AppName),
    io_lib:format(
        "module ~sTest\n"
        "  use Winn.Test\n"
        "\n"
        "  def test_hello()\n"
        "    assert(true)\n"
        "  end\n"
        "end\n", [Mod]).

scaffold_config(_AppName) ->
    "module Config\n"
    "  def database()\n"
    "    %{\n"
    "      adapter: :postgres,\n"
    "      hostname: System.get_env(\"DB_HOST\", \"localhost\"),\n"
    "      database: System.get_env(\"DB_NAME\", \"app_dev\"),\n"
    "      username: System.get_env(\"DB_USER\", \"postgres\"),\n"
    "      password: System.get_env(\"DB_PASS\", \"\"),\n"
    "      pool_size: 10\n"
    "    }\n"
    "  end\n"
    "\n"
    "  def port()\n"
    "    System.get_env(\"PORT\", \"4000\")\n"
    "  end\n"
    "end\n".

scaffold_seeds() ->
    "module Seeds\n"
    "  def run()\n"
    "    IO.puts(\"Seeding database...\")\n"
    "  end\n"
    "end\n".

scaffold_env_example() ->
    "# Database\n"
    "DB_HOST=localhost\n"
    "DB_NAME=app_dev\n"
    "DB_USER=postgres\n"
    "DB_PASS=\n"
    "\n"
    "# Server\n"
    "PORT=4000\n"
    "\n"
    "# Auth\n"
    "JWT_SECRET=change_me_in_production\n".

scaffold_readme(AppName) ->
    io_lib:format(
        "# ~s\n"
        "\n"
        "A [Winn](https://winn.ws) project.\n"
        "\n"
        "## Getting Started\n"
        "\n"
        "```sh\n"
        "winn run src/~s.winn\n"
        "```\n"
        "\n"
        "## Tests\n"
        "\n"
        "```sh\n"
        "winn test\n"
        "```\n"
        "\n"
        "## Project Structure\n"
        "\n"
        "```\n"
        "src/              Application source\n"
        "  models/         Data models and schemas\n"
        "  controllers/    Request handlers\n"
        "  tasks/          Background tasks\n"
        "test/             Tests\n"
        "config/           Configuration\n"
        "db/migrations/    Database migrations\n"
        "```\n", [AppName, filename:basename(AppName)]).

scaffold_rebar(AppName) ->
    io_lib:format(
        "{erl_opts, [debug_info]}.\n\n{deps, []}.\n\n"
        "{escript_main_app, ~s}.\n"
        "{escript_name, ~s}.\n",
        [AppName, AppName]).

scaffold_gitignore() ->
    "_build/\n"
    "ebin/\n"
    "*.beam\n"
    "_packages/\n"
    ".env\n"
    "*.swp\n"
    "*~\n"
    ".DS_Store\n".

scaffold_package_json(BaseName) ->
    io_lib:format(
        "{\n"
        "  \"name\": \"~s\",\n"
        "  \"version\": \"0.1.0\",\n"
        "  \"packages\": {}\n"
        "}\n", [BaseName]).

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

%% ── Benchmarking ────────────────────────────────────────────────────────

run_bench([File | _]) ->
    OutDir = "_build/bench",
    ok = filelib:ensure_path(OutDir),
    %% Compile src/ first (for project modules)
    SrcFiles = filelib:wildcard("src/*.winn"),
    lists:foreach(fun(F) ->
        case winn:compile_file(F, OutDir) of
            {ok, _} -> ok;
            _ -> ok
        end
    end, SrcFiles),
    %% Compile the bench file
    case winn:compile_file(File, OutDir) of
        {ok, _} ->
            code:add_patha(OutDir),
            ModAtom = detect_module_name(File),
            code:purge(ModAtom),
            code:load_file(ModAtom),
            case erlang:function_exported(ModAtom, '__bench__', 0) of
                true ->
                    winn_bench:run_benchmarks(ModAtom),
                    halt(0);
                false ->
                    io:format("Error: ~s does not export __bench__/0~n"
                              "Use `use Winn.Bench` and define bench blocks.~n", [ModAtom]),
                    halt(1)
            end;
        {error, Reason} ->
            io:format("Error compiling ~s: ~p~n", [File, Reason]),
            halt(1)
    end;
run_bench([]) ->
    io:format("Usage: winn bench <file>~n"),
    halt(0).

%% ── Release / deployment ────────────────────────────────────────────────

run_release(["--docker"]) ->
    generate_dockerfile(),
    halt(0);
run_release([]) ->
    io:format("Building release...~n"),
    %% Compile all Winn source first
    SrcFiles = filelib:wildcard("src/*.winn"),
    ok = filelib:ensure_path("ebin"),
    lists:foreach(fun(F) ->
        case winn:compile_file(F, "ebin") of
            {ok, _} -> ok;
            {error, _} -> ok
        end
    end, SrcFiles),
    %% Run rebar3 release
    case os:cmd("rebar3 as prod release 2>&1") of
        Output ->
            io:format("~s~n", [Output]),
            case string:find(Output, "Release successfully") of
                nomatch ->
                    %% Try tar if release not configured
                    io:format("~nTrying tarball...~n"),
                    TarOutput = os:cmd("rebar3 as prod tar 2>&1"),
                    io:format("~s~n", [TarOutput]),
                    halt(0);
                _ ->
                    halt(0)
            end
    end;
run_release(_) ->
    io:format("Usage:~n"
              "  winn release            Build a production release~n"
              "  winn release --docker   Generate a Dockerfile~n"),
    halt(0).

generate_dockerfile() ->
    Content = "FROM erlang:28-slim AS builder\n"
              "WORKDIR /app\n"
              "COPY rebar.config rebar.lock* ./\n"
              "RUN rebar3 get-deps\n"
              "COPY . .\n"
              "RUN rebar3 as prod release\n"
              "\n"
              "FROM debian:bookworm-slim\n"
              "RUN apt-get update && apt-get install -y libncurses5 libssl3 && rm -rf /var/lib/apt/lists/*\n"
              "WORKDIR /app\n"
              "COPY --from=builder /app/_build/prod/rel/ ./rel/\n"
              "ENV PORT=4000\n"
              "EXPOSE 4000\n"
              "CMD [\"./rel/*/bin/*\", \"foreground\"]\n",
    case filelib:is_file("Dockerfile") of
        true ->
            io:format("  exists  Dockerfile~n");
        false ->
            ok = file:write_file("Dockerfile", Content),
            io:format("  create  Dockerfile~n")
    end.

%% ── Code generators ─────────────────────────────────────────────────────

run_create(["model" | Rest]) when length(Rest) >= 1 ->
    winn_generator:generate(model, Rest),
    halt(0);
run_create(["migration" | Rest]) when length(Rest) >= 1 ->
    winn_generator:generate(migration, Rest),
    halt(0);
run_create(["task" | [Name]]) ->
    winn_generator:generate(task, [Name]),
    halt(0);
run_create(["router" | [Name]]) ->
    winn_generator:generate(router, [Name]),
    halt(0);
run_create(["scaffold" | Rest]) when length(Rest) >= 1 ->
    winn_generator:generate(scaffold, Rest),
    halt(0);
run_create(_) ->
    io:format("Usage:~n"
              "  winn create model <Name> [field:type ...]~n"
              "  winn create migration <Name> [field:type ...]~n"
              "  winn create task <name>~n"
              "  winn create router <Name>~n"
              "  winn create scaffold <Name> [field:type ...]~n"
              "~n"
              "Shorthand: winn c model User name:string~n"),
    halt(0).

%% ── Migration commands ──────────────────────────────────────────────────

run_migrate(["--status"]) ->
    winn_migrate:status(),
    halt(0);
run_migrate(["--step", N]) ->
    case winn_migrate:migrate(#{step => list_to_integer(N)}) of
        ok -> halt(0);
        _  -> halt(1)
    end;
run_migrate([]) ->
    case winn_migrate:migrate(#{}) of
        ok -> halt(0);
        _  -> halt(1)
    end;
run_migrate(_) ->
    io:format("Usage:~n"
              "  winn migrate              Run all pending migrations~n"
              "  winn migrate --step N     Run next N migrations~n"
              "  winn migrate --status     Show migration status~n"),
    halt(0).

run_rollback(["--step", N]) ->
    case winn_migrate:rollback(#{step => list_to_integer(N)}) of
        ok -> halt(0);
        _  -> halt(1)
    end;
run_rollback([]) ->
    case winn_migrate:rollback(#{}) of
        ok -> halt(0);
        _  -> halt(1)
    end;
run_rollback(_) ->
    io:format("Usage:~n"
              "  winn rollback             Rollback last migration~n"
              "  winn rollback --step N    Rollback last N migrations~n"),
    halt(0).

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

%% ── Formatter ───────────────────────────────────────────────────────────

run_fmt([]) ->
    Files = find_winn_files(),
    case Files of
        [] ->
            io:format("No .winn files found in src/ or current directory.~n"),
            halt(0);
        _ ->
            lists:foreach(fun(F) ->
                case winn_formatter:format_file(F) of
                    {ok, Formatted} ->
                        file:write_file(F, Formatted),
                        io:format("  formatted  ~s~n", [F]);
                    {error, Reason} ->
                        io:format("  error      ~s: ~p~n", [F, Reason])
                end
            end, Files),
            halt(0)
    end;
run_fmt(Files) ->
    lists:foreach(fun(F) ->
        case winn_formatter:format_file(F) of
            {ok, Formatted} ->
                file:write_file(F, Formatted),
                io:format("  formatted  ~s~n", [F]);
            {error, Reason} ->
                io:format("  error      ~s: ~p~n", [F, Reason])
        end
    end, Files),
    halt(0).

run_fmt_check([]) ->
    run_fmt_check(find_winn_files());
run_fmt_check(Files) ->
    Changed = lists:filtermap(fun(F) ->
        case winn_formatter:check_file(F) of
            ok -> false;
            {changed, _} ->
                io:format("  unformatted  ~s~n", [F]),
                {true, F}
        end
    end, Files),
    case Changed of
        [] ->
            io:format("All files formatted.~n"),
            halt(0);
        _ ->
            io:format("~B file(s) need formatting. Run `winn fmt` to fix.~n", [length(Changed)]),
            halt(1)
    end.

find_winn_files() ->
    SrcFiles = filelib:wildcard("src/*.winn"),
    case SrcFiles of
        [] -> filelib:wildcard("*.winn");
        _  -> SrcFiles
    end.

%% ── Lint ────────────────────────────────────────────────────────────────

run_lint([]) ->
    Files = find_winn_files(),
    case Files of
        [] ->
            io:format("No .winn files found in src/ or current directory.~n"),
            halt(0);
        _ ->
            run_lint(Files)
    end;
run_lint(Files) ->
    AllViolations = lists:flatmap(fun(F) ->
        case winn_lint:check_file(F) of
            {ok, []} ->
                [];
            {ok, Violations} ->
                {ok, Bin} = file:read_file(F),
                Source = binary_to_list(Bin),
                Formatted = winn_errors:format_diagnostics(Violations, Source, F),
                io:put_chars(standard_error, Formatted),
                Violations;
            {error, Reason} ->
                io:format(standard_error, "  error  ~s: ~p~n", [F, Reason]),
                [Reason]
        end
    end, Files),
    case AllViolations of
        [] ->
            io:format("No lint warnings.~n"),
            halt(0);
        _ ->
            io:format(standard_error, "~B warning(s) found.~n", [length(AllViolations)]),
            halt(1)
    end.

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
        _         -> "0.9.1"
    end.

print_version() ->
    io:format("winn ~s~n", [get_version()]).

print_usage() ->
    io:format(
        "Winn ~s - a compiled language on the BEAM~n~n"
        "Development:~n"
        "  new <name> [flags]  Create a new project (--api, --minimal)~n"
        "  r, run <file>       Compile and run a file~n"
        "  s, start [module]   Start project (keeps VM alive)~n"
        "  t, test [file]      Run tests~n"
        "  w, watch [--start]  Watch + hot-reload~n"
        "  con, console        Interactive REPL~n~n"
        "Code Quality:~n"
        "  c, compile [file]   Compile .winn files~n"
        "  f, fmt [file]       Format code (--check for CI)~n"
        "  l, lint [file]      Static analysis~n"
        "  d, docs [file]      Generate API docs~n"
        "  lsp                 Start language server (stdio)~n~n"
        "Generators:~n"
        "  g, create <type>    Generate code (model, migration, ...)~n"
        "  task <name>         Run a project task~n"
        "  migrate             Run pending migrations~n"
        "  rollback            Rollback last migration~n~n"
        "Packages:~n"
        "  add <pkg>           Install a package~n"
        "  remove <pkg>        Remove a package~n"
        "  packages            List installed~n"
        "  install             Install all from package.json~n"
        "  deps                Manage Erlang dependencies~n~n"
        "Production:~n"
        "  bench <file>        Load testing~n"
        "  metrics             Live metrics dashboard~n"
        "  release [--docker]  Build production release~n~n"
        "  -v, version         Show version~n"
        "  -h, help            Show this help~n",
        [get_version()]
    ).

-module(winn_phase6_tests).
-include_lib("eunit/include/eunit.hrl").

lex(Src)       -> {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_), Tokens.
parse(Src)     -> {ok, Forms} = winn_parser:parse(lex(Src)), Forms.
transform(Src) -> winn_transform:transform(parse(Src)).
load_src(Src) ->
    Forms = transform(Src),
    [CoreMod | _] = winn_codegen:gen(Forms),
    {ok, ModName, Bin} = winn_core_emit:emit_to_binary(CoreMod),
    {module, ModName} = code:load_binary(ModName, "nofile", Bin),
    ModName.

%% ── parse_args tests ──────────────────────────────────────────────────────

parse_args_new_test() ->
    ?assertEqual({new, "foo", #{mode => default}}, winn_cli:parse_args(["new", "foo"])).

parse_args_new_api_test() ->
    ?assertEqual({new, "foo", #{mode => api}}, winn_cli:parse_args(["new", "foo", "--api"])).

parse_args_new_minimal_test() ->
    ?assertEqual({new, "foo", #{mode => minimal}}, winn_cli:parse_args(["new", "foo", "--minimal"])).

parse_args_compile_no_files_test() ->
    ?assertEqual({compile, []}, winn_cli:parse_args(["compile"])).

parse_args_compile_with_file_test() ->
    ?assertEqual({compile, ["file.winn"]}, winn_cli:parse_args(["compile", "file.winn"])).

parse_args_run_no_args_test() ->
    ?assertEqual({run, "file.winn", []}, winn_cli:parse_args(["run", "file.winn"])).

parse_args_run_with_args_test() ->
    ?assertEqual({run, "file.winn", ["arg1"]}, winn_cli:parse_args(["run", "file.winn", "arg1"])).

parse_args_help_test() ->
    ?assertEqual(help, winn_cli:parse_args(["help"])).

parse_args_empty_test() ->
    ?assertEqual(help, winn_cli:parse_args([])).

parse_args_unknown_test() ->
    ?assertEqual(unknown, winn_cli:parse_args(["unknown"])).

%% ── scaffold tests ────────────────────────────────────────────────────────

scaffold_creates_dir_test() ->
    TmpDir = "/tmp/winn_test_scaffold_" ++ integer_to_list(erlang:unique_integer([positive])),
    try
        winn_cli:scaffold(TmpDir),
        ?assert(filelib:is_dir(TmpDir))
    after
        os:cmd("rm -rf " ++ TmpDir)
    end.

scaffold_creates_src_subdir_test() ->
    TmpDir = "/tmp/winn_test_scaffold_" ++ integer_to_list(erlang:unique_integer([positive])),
    try
        winn_cli:scaffold(TmpDir),
        ?assert(filelib:is_dir(filename:join(TmpDir, "src")))
    after
        os:cmd("rm -rf " ++ TmpDir)
    end.

scaffold_creates_winn_source_file_test() ->
    TmpDir = "/tmp/winn_test_scaffold_" ++ integer_to_list(erlang:unique_integer([positive])),
    AppName = filename:basename(TmpDir),
    try
        winn_cli:scaffold(TmpDir),
        WinnFile = filename:join([TmpDir, "src", AppName ++ ".winn"]),
        ?assert(filelib:is_regular(WinnFile))
    after
        os:cmd("rm -rf " ++ TmpDir)
    end.

scaffold_creates_rebar_config_test() ->
    TmpDir = "/tmp/winn_test_scaffold_" ++ integer_to_list(erlang:unique_integer([positive])),
    try
        winn_cli:scaffold(TmpDir),
        ?assert(filelib:is_regular(filename:join(TmpDir, "rebar.config")))
    after
        os:cmd("rm -rf " ++ TmpDir)
    end.

%% ── compile integration tests ─────────────────────────────────────────────

compile_string_returns_ok_test() ->
    Src = "module CompileTest6\n"
          "  def greet() :hello end\n"
          "end",
    TmpDir = "/tmp/winn_test_compile_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_dir(TmpDir ++ "/"),
    try
        Result = winn:compile_string(Src, "compile_test6.winn", TmpDir),
        ?assertMatch({ok, [_]}, Result)
    after
        os:cmd("rm -rf " ++ TmpDir)
    end.

compile_string_produces_callable_module_test() ->
    Src = "module CompileLoad6\n"
          "  def answer() 42 end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(42, ModName:answer()).

compile_file_test() ->
    TmpDir = "/tmp/winn_test_file_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_dir(TmpDir ++ "/"),
    WinnFile = filename:join(TmpDir, "file_test6.winn"),
    Src = "module FileTest6\n"
          "  def value() :ok end\n"
          "end",
    try
        ok = file:write_file(WinnFile, Src),
        Result = winn:compile_file(WinnFile, TmpDir),
        ?assertMatch({ok, [_]}, Result)
    after
        os:cmd("rm -rf " ++ TmpDir)
    end.

%% ── run integration tests ─────────────────────────────────────────────────

run_hello_returns_atom_test() ->
    Src = "module RunTest6\n"
          "  def hello() :world end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(world, ModName:hello()).

run_main_callable_test() ->
    Src = "module MainTest6\n"
          "  def main() :done end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(done, ModName:main()).

run_arithmetic_test() ->
    Src = "module ArithTest6\n"
          "  def add() 1 + 2 end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(3, ModName:add()).

%% ── regression ────────────────────────────────────────────────────────────

hello_regression_test() ->
    Src = "module Hello6\n"
          "  def main() IO.puts(\"Hello from Phase 6!\") end\n"
          "end",
    Forms = transform(Src),
    [CoreMod | _] = winn_codegen:gen(Forms),
    {ok, _, Bin} = winn_core_emit:emit_to_binary(CoreMod),
    ?assert(is_binary(Bin)).

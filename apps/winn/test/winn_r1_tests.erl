%% winn_r1_tests.erl — R1: System environment variables.

-module(winn_r1_tests).
-include_lib("eunit/include/eunit.hrl").

compile_and_load(Source) ->
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── Direct runtime tests ────────────────────────────────────────────────

get_env_missing_test() ->
    ?assertEqual(nil, winn_runtime:'system.get_env'(<<"WINN_TEST_MISSING_XYZ">>)).

get_env_present_test() ->
    os:putenv("WINN_TEST_R1", "hello"),
    ?assertEqual(<<"hello">>, winn_runtime:'system.get_env'(<<"WINN_TEST_R1">>)),
    os:unsetenv("WINN_TEST_R1").

get_env_default_test() ->
    ?assertEqual(<<"fallback">>, winn_runtime:'system.get_env'(<<"WINN_TEST_MISSING_XYZ">>, <<"fallback">>)).

put_env_test() ->
    winn_runtime:'system.put_env'(<<"WINN_TEST_R1_PUT">>, <<"world">>),
    ?assertEqual(<<"world">>, winn_runtime:'system.get_env'(<<"WINN_TEST_R1_PUT">>)),
    os:unsetenv("WINN_TEST_R1_PUT").

%% ── End-to-end compilation test ─────────────────────────────────────────

e2e_get_env_test() ->
    os:putenv("WINN_R1_E2E", "42"),
    Src = "module SysTest\n  def run()\n    System.get_env(\"WINN_R1_E2E\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"42">>, Mod:run()),
    os:unsetenv("WINN_R1_E2E").

e2e_get_env_default_test() ->
    Src = "module SysDef\n  def run()\n    System.get_env(\"WINN_NOPE\", \"default_val\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"default_val">>, Mod:run()).

e2e_put_env_test() ->
    Src = "module SysPut\n  def run()\n    System.put_env(\"WINN_R1_PUT_E2E\", \"yes\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(ok, Mod:run()),
    ?assertEqual(<<"yes">>, winn_runtime:'system.get_env'(<<"WINN_R1_PUT_E2E">>)),
    os:unsetenv("WINN_R1_PUT_E2E").

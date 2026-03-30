%% winn_test_framework_tests.erl
%% Tests for the Winn testing framework (winn test).

-module(winn_test_framework_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Helpers ──────────────────────────────────────────────────────────────────

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

%% ── Assert runtime tests ────────────────────────────────────────────────────

assert_true_test() ->
    ?assertEqual(ok, winn_test:assert(true)).

assert_false_test() ->
    ?assertError({assertion_failed, #{expected := true, got := false}},
                 winn_test:assert(false)).

assert_non_boolean_test() ->
    ?assertError({assertion_failed, #{expected := true, got := 42}},
                 winn_test:assert(42)).

assert_equal_pass_test() ->
    ?assertEqual(ok, winn_test:assert_equal(42, 42)).

assert_equal_fail_test() ->
    ?assertError({assertion_failed, #{expected := 42, got := 99}},
                 winn_test:assert_equal(42, 99)).

assert_equal_string_test() ->
    ?assertEqual(ok, winn_test:assert_equal(<<"hello">>, <<"hello">>)).

%% ── Transform: use Winn.Test ────────────────────────────────────────────────

use_winn_test_transform_test() ->
    Source = "module TestTransformCheck\n"
             "  use Winn.Test\n"
             "\n"
             "  def test_example()\n"
             "    1 + 1\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    %% Should contain a behaviour_attr for winn_test
    [{module, _, _, Body}] = Transformed,
    BehaviourAttrs = [B || {behaviour_attr, _, B} <- Body],
    ?assert(lists:member(winn_test, BehaviourAttrs)).

%% ── End-to-end: compile and run assert ──────────────────────────────────────

assert_compiles_and_passes_test() ->
    Source = "module TestAssertPass\n"
             "  use Winn.Test\n"
             "\n"
             "  def test_truth()\n"
             "    assert(1 == 1)\n"
             "  end\n"
             "end\n",
    Mod = compile_and_load(Source),
    ?assertEqual(ok, Mod:test_truth()).

assert_compiles_and_fails_test() ->
    Source = "module TestAssertFail\n"
             "  use Winn.Test\n"
             "\n"
             "  def test_lie()\n"
             "    assert(1 == 2)\n"
             "  end\n"
             "end\n",
    Mod = compile_and_load(Source),
    ?assertError({assertion_failed, _}, Mod:test_lie()).

assert_equal_compiles_test() ->
    Source = "module TestAssertEqualComp\n"
             "  use Winn.Test\n"
             "\n"
             "  def test_eq()\n"
             "    assert_equal(42, 21 + 21)\n"
             "  end\n"
             "end\n",
    Mod = compile_and_load(Source),
    ?assertEqual(ok, Mod:test_eq()).

assert_equal_fail_compiles_test() ->
    Source = "module TestAssertEqualFail\n"
             "  use Winn.Test\n"
             "\n"
             "  def test_neq()\n"
             "    assert_equal(42, 99)\n"
             "  end\n"
             "end\n",
    Mod = compile_and_load(Source),
    ?assertError({assertion_failed, _}, Mod:test_neq()).

%% ── Test runner: discover and run ───────────────────────────────────────────

run_tests_all_pass_test() ->
    Source = "module TestRunnerPass\n"
             "  use Winn.Test\n"
             "\n"
             "  def test_one()\n"
             "    assert(true)\n"
             "  end\n"
             "\n"
             "  def test_two()\n"
             "    assert_equal(4, 2 + 2)\n"
             "  end\n"
             "end\n",
    Mod = compile_and_load(Source),
    ?assertEqual(ok, winn_test:run_tests([Mod])).

run_tests_with_failure_test() ->
    Source = "module TestRunnerMixed\n"
             "  use Winn.Test\n"
             "\n"
             "  def test_pass()\n"
             "    assert(true)\n"
             "  end\n"
             "\n"
             "  def test_fail()\n"
             "    assert(false)\n"
             "  end\n"
             "end\n",
    Mod = compile_and_load(Source),
    ?assertEqual(error, winn_test:run_tests([Mod])).

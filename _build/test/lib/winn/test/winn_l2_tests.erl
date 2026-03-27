%% winn_l2_tests.erl — L2: switch expression tests.

-module(winn_l2_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Helpers ──────────────────────────────────────────────────────────────

compile_and_load(Source) ->
    {ok, Tokens, _} = winn_lexer:string(Source),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── Parse tests ─────────────────────────────────────────────────────────

parse_switch_test() ->
    Src = "module Test\n  def foo(x)\n    switch x\n      :a => 1\n      :b => 2\n      _ => 0\n    end\n  end\nend\n",
    {ok, Tokens, _} = winn_lexer:string(Src),
    {ok, AST} = winn_parser:parse(Tokens),
    ?assertMatch([{module, _, 'Test', _}], AST).

%% ── Transform tests ─────────────────────────────────────────────────────

transform_switch_to_case_test() ->
    Src = "module Test\n  def foo(x)\n    switch x\n      :a => 1\n      _ => 0\n    end\n  end\nend\n",
    {ok, Tokens, _} = winn_lexer:string(Src),
    {ok, AST} = winn_parser:parse(Tokens),
    [{module, _, 'Test', Body}] = winn_transform:transform(AST),
    %% Outer case wraps param, inner case is the switch desugaring.
    [{function, _, foo, _, [{case_expr, _, _, [{case_clause, _, _, _, [SwitchCase]}]}]}] = Body,
    {case_expr, _, _, Clauses} = SwitchCase,
    ?assertEqual(2, length(Clauses)).

%% ── End-to-end tests ────────────────────────────────────────────────────

switch_atom_match_test() ->
    Src = "module SwAtom\n  def check(x)\n    switch x\n      :active => 1\n      :inactive => 2\n      _ => 0\n    end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(1, Mod:check(active)),
    ?assertEqual(2, Mod:check(inactive)),
    ?assertEqual(0, Mod:check(unknown)).

switch_integer_match_test() ->
    Src = "module SwInt\n  def describe(n)\n    switch n\n      1 => :one\n      2 => :two\n      _ => :other\n    end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(one, Mod:describe(1)),
    ?assertEqual(two, Mod:describe(2)),
    ?assertEqual(other, Mod:describe(99)).

switch_as_expression_test() ->
    Src = "module SwExpr\n  def run(x)\n    result = switch x\n      :yes => 100\n      _ => 0\n    end\n    result\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(100, Mod:run(yes)),
    ?assertEqual(0, Mod:run(no)).

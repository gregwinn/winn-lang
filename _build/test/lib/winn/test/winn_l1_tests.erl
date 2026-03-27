%% winn_l1_tests.erl — L1: if/else expression tests.

-module(winn_l1_tests).
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

parse_if_else_test() ->
    Src = "module Test\n  def foo()\n    if true\n      1\n    else\n      2\n    end\n  end\nend\n",
    {ok, Tokens, _} = winn_lexer:string(Src),
    {ok, AST} = winn_parser:parse(Tokens),
    ?assertMatch([{module, _, 'Test', _}], AST).

parse_if_no_else_test() ->
    Src = "module Test\n  def foo()\n    if true\n      1\n    end\n  end\nend\n",
    {ok, Tokens, _} = winn_lexer:string(Src),
    {ok, AST} = winn_parser:parse(Tokens),
    ?assertMatch([{module, _, 'Test', _}], AST).

%% ── Transform tests ─────────────────────────────────────────────────────

transform_if_else_test() ->
    Src = "module Test\n  def foo()\n    if true\n      1\n    else\n      2\n    end\n  end\nend\n",
    {ok, Tokens, _} = winn_lexer:string(Src),
    {ok, AST} = winn_parser:parse(Tokens),
    [{module, _, 'Test', Body}] = winn_transform:transform(AST),
    %% No params, so case-wrap has 0-arity; inner body has the if→case.
    [{function, _, foo, _, [{case_expr, _, _, [{case_clause, _, _, _, [IfCase]}]}]}] = Body,
    {case_expr, _, _, Clauses} = IfCase,
    ?assertEqual(2, length(Clauses)).

transform_if_no_else_test() ->
    Src = "module Test\n  def foo()\n    if true\n      1\n    end\n  end\nend\n",
    {ok, Tokens, _} = winn_lexer:string(Src),
    {ok, AST} = winn_parser:parse(Tokens),
    [{module, _, 'Test', Body}] = winn_transform:transform(AST),
    [{function, _, foo, _, [{case_expr, _, _, [{case_clause, _, _, _, [IfCase]}]}]}] = Body,
    {case_expr, _, _, Clauses} = IfCase,
    ?assertEqual(1, length(Clauses)).

%% ── End-to-end tests ────────────────────────────────────────────────────

if_true_branch_test() ->
    Src = "module IfTrue\n  def run()\n    if true\n      42\n    else\n      0\n    end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(42, Mod:run()).

if_false_branch_test() ->
    Src = "module IfFalse\n  def run()\n    if false\n      42\n    else\n      0\n    end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(0, Mod:run()).

if_as_expression_test() ->
    Src = "module IfExpr\n  def run()\n    x = if true\n      100\n    else\n      200\n    end\n    x\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(100, Mod:run()).

if_with_comparison_test() ->
    Src = "module IfCmp\n  def check(n)\n    if n > 0\n      :positive\n    else\n      :non_positive\n    end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(positive, Mod:check(5)),
    ?assertEqual(non_positive, Mod:check(-1)),
    ?assertEqual(non_positive, Mod:check(0)).

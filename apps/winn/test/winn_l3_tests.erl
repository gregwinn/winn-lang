%% winn_l3_tests.erl — L3: Guards (when) tests.

-module(winn_l3_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Helpers ──────────────────────────────────────────────────────────────

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

%% ── Parse tests ─────────────────────────────────────────────────────────

parse_guarded_function_test() ->
    Src = "module Test\n  def abs(n) when n > 0\n    n\n  end\n  def abs(n)\n    0 - n\n  end\nend\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, AST} = winn_parser:parse(Tokens),
    ?assertMatch([{module, _, 'Test', _}], AST).

%% ── Transform tests ─────────────────────────────────────────────────────

transform_guarded_fn_test() ->
    Src = "module Test\n  def abs(n) when n > 0\n    n\n  end\n  def abs(n)\n    0 - n\n  end\nend\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, AST} = winn_parser:parse(Tokens),
    [{module, _, 'Test', Body}] = winn_transform:transform(AST),
    %% Both clauses are case-wrapped, so they should merge into 1 function with 2 clauses.
    ?assertMatch([{function, _, abs, _, [{case_expr, _, _, [_,_]}]}], Body).

%% ── End-to-end tests ────────────────────────────────────────────────────

guarded_function_test() ->
    Src = "module GuardFn\n  def abs(n) when n > 0\n    n\n  end\n  def abs(n)\n    0 - n\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(5, Mod:abs(5)),
    ?assertEqual(3, Mod:abs(-3)).

guarded_switch_clause_test() ->
    Src = "module GuardSw\n  def classify(n)\n    switch n\n      x when x > 0 => :positive\n      x when x < 0 => :negative\n      _ => :zero\n    end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(positive, Mod:classify(10)),
    ?assertEqual(negative, Mod:classify(-5)),
    ?assertEqual(zero, Mod:classify(0)).

multiple_guarded_clauses_test() ->
    Src = "module GuardMulti\n  def grade(score) when score >= 90\n    :a\n  end\n  def grade(score) when score >= 80\n    :b\n  end\n  def grade(score) when score >= 70\n    :c\n  end\n  def grade(_)\n    :f\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(a, Mod:grade(95)),
    ?assertEqual(b, Mod:grade(85)),
    ?assertEqual(c, Mod:grade(75)),
    ?assertEqual(f, Mod:grade(50)).

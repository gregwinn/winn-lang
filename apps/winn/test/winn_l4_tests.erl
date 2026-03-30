%% winn_l4_tests.erl — L4: try/rescue tests.

-module(winn_l4_tests).
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

parse_try_rescue_test() ->
    Src = "module Test\n  def foo()\n    try\n      1\n    rescue\n      _ => 0\n    end\n  end\nend\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, AST} = winn_parser:parse(Tokens),
    ?assertMatch([{module, _, 'Test', _}], AST).

%% ── Transform tests ─────────────────────────────────────────────────────

transform_try_rescue_test() ->
    Src = "module Test\n  def foo()\n    try\n      1\n    rescue\n      _ => 0\n    end\n  end\nend\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, AST} = winn_parser:parse(Tokens),
    [{module, _, 'Test', Body}] = winn_transform:transform(AST),
    %% Body is case-wrapped (0-arity), inner body has the try_expr.
    [{function, _, foo, _, [{case_expr, _, _, [{case_clause, _, _, _, [TryExpr]}]}]}] = Body,
    ?assertMatch({try_expr, _, _, _}, TryExpr).

%% ── End-to-end tests ────────────────────────────────────────────────────

try_no_error_test() ->
    Src = "module TryOk\n  def run()\n    try\n      42\n    rescue\n      _ => 0\n    end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(42, Mod:run()).

try_catch_wildcard_test() ->
    %% Throw a value and catch it with wildcard.
    Src = "module TryCatch\n  def run()\n    try\n      Erlang.throw(:boom)\n    rescue\n      _ => :caught\n    end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(caught, Mod:run()).

try_catch_pattern_test() ->
    %% Throw a tuple and match it in rescue.
    Src = "module TryPat\n  def run()\n    try\n      Erlang.throw({:error, :bad})\n    rescue\n      {:error, :bad} => :matched\n      _ => :other\n    end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(matched, Mod:run()).

try_as_expression_test() ->
    Src = "module TryExpr\n  def run()\n    result = try\n      100\n    rescue\n      _ => 0\n    end\n    result\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(100, Mod:run()).

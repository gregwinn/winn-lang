%% winn_highimpact_tests.erl — Tests for high-impact language features:
%% string interpolation, map field access, lambdas, pattern assignment,
%% JSON module, for comprehensions.

-module(winn_highimpact_tests).
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

%% ── String Interpolation ────────────────────────────────────────────────

interp_lex_test() ->
    {ok, RawTok_, _} = winn_lexer:string("\"Hello, #{name}!\""), Tokens = winn_newline_filter:filter(RawTok_),
    ?assertMatch([{interp_string, _, [{str, <<"Hello, ">>}, {expr, "name"}, {str, <<"!">>}]}], Tokens).

interp_plain_string_test() ->
    %% No interpolation — should be a regular string_lit.
    {ok, RawTok_, _} = winn_lexer:string("\"Hello, World!\""), Tokens = winn_newline_filter:filter(RawTok_),
    ?assertMatch([{string_lit, _, <<"Hello, World!">>}], Tokens).

interp_e2e_test() ->
    Src = "module InterpE2e\n  def greet(name)\n    \"Hello, #{name}!\"\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"Hello, Alice!">>, Mod:greet(<<"Alice">>)).

interp_number_test() ->
    Src = "module InterpNum\n  def show(n)\n    \"count: #{n}\"\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"count: 42">>, Mod:show(42)).

interp_multiple_test() ->
    Src = "module InterpMulti\n  def show(a, b)\n    \"#{a} and #{b}\"\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"hello and world">>, Mod:show(<<"hello">>, <<"world">>)).

interp_escaped_test() ->
    %% \#{} should NOT interpolate (backslash escapes the #).
    {ok, RawTok_, _} = winn_lexer:string("\"Hello, \\#{name}\""), Tokens = winn_newline_filter:filter(RawTok_),
    %% The backslash is preserved by the lexer's unescape — \# isn't a standard
    %% escape sequence, so it passes through as \#. The key point is no interpolation.
    ?assertMatch([{string_lit, _, _}], Tokens).

%% ── Map Field Access ────────────────────────────────────────────────────

field_access_parse_test() ->
    Src = "module FaTest\n  def get_name(user)\n    user.name\n  end\nend\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, _AST} = winn_parser:parse(Tokens).

field_access_e2e_test() ->
    Src = "module FaE2e\n  def get_name(user)\n    user.name\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"Alice">>, Mod:get_name(#{name => <<"Alice">>})).

field_access_nested_test() ->
    Src = "module FaNested\n  def get_status(resp)\n    resp.status\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(200, Mod:get_status(#{status => 200, body => <<>>})).

%% ── Standalone Lambdas ──────────────────────────────────────────────────

lambda_parse_test() ->
    Src = "module LamTest\n  def run()\n    f = fn(x) => x * 2 end\n    f(5)\n  end\nend\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, _AST} = winn_parser:parse(Tokens).

lambda_e2e_test() ->
    %% Test that fn creates a callable function value.
    Src = "module LamE2e\n  def make_adder(n)\n    fn(x) => x + n end\n  end\nend\n",
    Mod = compile_and_load(Src),
    Adder = Mod:make_adder(10),
    ?assertEqual(15, Adder(5)).

lambda_no_args_test() ->
    Src = "module LamNoArgs\n  def make_const()\n    fn() => 42 end\n  end\nend\n",
    Mod = compile_and_load(Src),
    F = Mod:make_const(),
    ?assertEqual(42, F()).

lambda_multi_args_test() ->
    Src = "module LamMulti\n  def make_add()\n    fn(a, b) => a + b end\n  end\nend\n",
    Mod = compile_and_load(Src),
    F = Mod:make_add(),
    ?assertEqual(7, F(3, 4)).

%% ── Pattern Assignment ──────────────────────────────────────────────────

pat_assign_parse_test() ->
    Src = "module PatTest\n  def run()\n    {:ok, x} = {:ok, 42}\n    x\n  end\nend\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, _AST} = winn_parser:parse(Tokens).

pat_assign_e2e_test() ->
    Src = "module PatE2e\n  def run()\n    {:ok, val} = {:ok, 99}\n    val\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(99, Mod:run()).

pat_assign_nested_test() ->
    Src = "module PatNested\n  def run()\n    {:ok, {a, b}} = {:ok, {1, 2}}\n    a + b\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(3, Mod:run()).

%% ── JSON Module ─────────────────────────────────────────────────────────

json_encode_test() ->
    Result = winn_json:encode(#{name => <<"Alice">>, age => 30}),
    ?assert(is_binary(Result)),
    Decoded = winn_json:decode(Result),
    ?assertEqual(<<"Alice">>, maps:get(name, Decoded)),
    ?assertEqual(30, maps:get(age, Decoded)).

json_decode_test() ->
    Result = winn_json:decode(<<"{\"name\":\"Bob\",\"count\":5}">>),
    ?assertEqual(<<"Bob">>, maps:get(name, Result)),
    ?assertEqual(5, maps:get(count, Result)).

json_roundtrip_test() ->
    Original = #{users => [#{id => 1}, #{id => 2}]},
    Encoded = winn_json:encode(Original),
    Decoded = winn_json:decode(Encoded),
    ?assertEqual([#{id => 1}, #{id => 2}], maps:get(users, Decoded)).

json_e2e_test() ->
    Src = "module JsonE2e\n  def run()\n    JSON.encode(%{name: \"test\"})\n  end\nend\n",
    Mod = compile_and_load(Src),
    Result = Mod:run(),
    ?assert(is_binary(Result)),
    Decoded = winn_json:decode(Result),
    ?assertEqual(<<"test">>, maps:get(name, Decoded)).

json_decode_e2e_test() ->
    Src = "module JsonDec\n  def run(data)\n    JSON.decode(data)\n  end\nend\n",
    Mod = compile_and_load(Src),
    Result = Mod:run(<<"{\"x\":1}">>),
    ?assertEqual(1, maps:get(x, Result)).

%% ── For Comprehensions ──────────────────────────────────────────────────

for_parse_test() ->
    Src = "module ForTest\n  def run(list)\n    for x in list do x * 2 end\n  end\nend\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, _AST} = winn_parser:parse(Tokens).

for_e2e_test() ->
    Src = "module ForE2e\n  def run(list)\n    for x in list do x * 2 end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual([2, 4, 6], Mod:run([1, 2, 3])).

for_with_call_test() ->
    Src = "module ForCall\n  def run(list)\n    for x in list do x + 10 end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual([11, 12, 13], Mod:run([1, 2, 3])).

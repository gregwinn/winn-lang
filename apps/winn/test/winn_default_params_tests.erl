%% winn_default_params_tests.erl
%% Tests for default parameter values (#39).

-module(winn_default_params_tests).
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

%% ── Parser ──────────────────────────────────────────────────────────────────

default_param_parses_test() ->
    Source = "module DpParse\n  def greet(name, g = \"Hi\")\n    g\n  end\nend\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, [{module, _, _, [{function, _, greet, Params, _}]}]} = winn_parser:parse(Tokens),
    ?assertMatch([{var, _, name}, {default_param, _, g, {string, _, <<"Hi">>}}], Params).

%% ── Single default ──────────────────────────────────────────────────────────

single_default_with_value_test() ->
    Mod = compile_and_load(
        "module DpSingle1\n"
        "  def greet(name, greeting = \"Hello\")\n"
        "    greeting <> \", \" <> name\n"
        "  end\n"
        "end\n"),
    ?assertEqual(<<"Hello, Alice">>, Mod:greet(<<"Alice">>)).

single_default_override_test() ->
    Mod = compile_and_load(
        "module DpSingle2\n"
        "  def greet(name, greeting = \"Hello\")\n"
        "    greeting <> \", \" <> name\n"
        "  end\n"
        "end\n"),
    ?assertEqual(<<"Hi, Alice">>, Mod:greet(<<"Alice">>, <<"Hi">>)).

%% ── Multiple defaults ───────────────────────────────────────────────────────

multiple_defaults_none_provided_test() ->
    Mod = compile_and_load(
        "module DpMulti1\n"
        "  def make(name, age = 0, active = true)\n"
        "    {name, age, active}\n"
        "  end\n"
        "end\n"),
    ?assertEqual({<<"Alice">>, 0, true}, Mod:make(<<"Alice">>)).

multiple_defaults_one_provided_test() ->
    Mod = compile_and_load(
        "module DpMulti2\n"
        "  def make(name, age = 0, active = true)\n"
        "    {name, age, active}\n"
        "  end\n"
        "end\n"),
    ?assertEqual({<<"Alice">>, 30, true}, Mod:make(<<"Alice">>, 30)).

multiple_defaults_all_provided_test() ->
    Mod = compile_and_load(
        "module DpMulti3\n"
        "  def make(name, age = 0, active = true)\n"
        "    {name, age, active}\n"
        "  end\n"
        "end\n"),
    ?assertEqual({<<"Alice">>, 30, false}, Mod:make(<<"Alice">>, 30, false)).

%% ── Integer default ─────────────────────────────────────────────────────────

integer_default_test() ->
    Mod = compile_and_load(
        "module DpInt\n"
        "  def add(a, b = 10)\n"
        "    a + b\n"
        "  end\n"
        "end\n"),
    ?assertEqual(15, Mod:add(5)),
    ?assertEqual(8, Mod:add(5, 3)).

%% ── Atom default ────────────────────────────────────────────────────────────

atom_default_test() ->
    Mod = compile_and_load(
        "module DpAtom\n"
        "  def status(val, default = :pending)\n"
        "    {val, default}\n"
        "  end\n"
        "end\n"),
    ?assertEqual({42, pending}, Mod:status(42)),
    ?assertEqual({42, active}, Mod:status(42, active)).

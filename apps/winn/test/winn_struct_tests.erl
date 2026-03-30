%% winn_struct_tests.erl
%% Tests for struct types (#13).

-module(winn_struct_tests).
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

struct_parses_test() ->
    Source = "module Pt\n  struct [:name, :age]\nend\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, [{module, _, 'Pt', Body}]} = winn_parser:parse(Tokens),
    ?assertMatch([{struct_def, _, [name, age]}], [S || {struct_def, _, _} = S <- Body]).

%% ── new/0 returns defaults ──────────────────────────────────────────────────

struct_new_defaults_test() ->
    Mod = compile_and_load(
        "module StNew0\n  struct [:name, :email]\nend\n"),
    Result = Mod:new(),
    ?assertEqual(nil, maps:get(name, Result)),
    ?assertEqual(nil, maps:get(email, Result)),
    ?assertEqual(stnew0, maps:get('__struct__', Result)).

%% ── new/1 merges attributes ────────────────────────────────────────────────

struct_new_with_attrs_test() ->
    Mod = compile_and_load(
        "module StNew1\n  struct [:name, :age]\nend\n"),
    Result = Mod:new(#{name => <<"Alice">>, age => 30}),
    ?assertEqual(<<"Alice">>, maps:get(name, Result)),
    ?assertEqual(30, maps:get(age, Result)),
    ?assertEqual(stnew1, maps:get('__struct__', Result)).

%% ── __struct__/0 returns module atom ────────────────────────────────────────

struct_type_test() ->
    Mod = compile_and_load(
        "module StType\n  struct [:x]\nend\n"),
    ?assertEqual(sttype, Mod:'__struct__'()).

%% ── __fields__/0 returns field list ─────────────────────────────────────────

struct_fields_test() ->
    Mod = compile_and_load(
        "module StFields\n  struct [:a, :b, :c]\nend\n"),
    ?assertEqual([a, b, c], Mod:'__fields__'()).

%% ── Field access via dot notation ───────────────────────────────────────────

struct_field_access_test() ->
    Mod = compile_and_load(
        "module StAccess\n"
        "  struct [:name, :age]\n"
        "\n"
        "  def run()\n"
        "    user = StAccess.new(%{name: \"Bob\", age: 25})\n"
        "    {user.name, user.age}\n"
        "  end\n"
        "end\n"),
    ?assertEqual({<<"Bob">>, 25}, Mod:run()).

%% ── Struct with functions ───────────────────────────────────────────────────

struct_with_methods_test() ->
    Mod = compile_and_load(
        "module StMethod\n"
        "  struct [:name]\n"
        "\n"
        "  def greet(user)\n"
        "    \"Hello, \" <> user.name\n"
        "  end\n"
        "\n"
        "  def run()\n"
        "    user = StMethod.new(%{name: \"Alice\"})\n"
        "    greet(user)\n"
        "  end\n"
        "end\n"),
    ?assertEqual(<<"Hello, Alice">>, Mod:run()).

%% ── Struct identity via __struct__ key ──────────────────────────────────────

struct_identity_test() ->
    Mod = compile_and_load(
        "module StIdent\n"
        "  struct [:val]\n"
        "\n"
        "  def run()\n"
        "    s = StIdent.new(%{val: 42})\n"
        "    s.__struct__\n"
        "  end\n"
        "end\n"),
    ?assertEqual(stident, Mod:run()).

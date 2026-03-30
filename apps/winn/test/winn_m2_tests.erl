%% winn_m2_tests.erl — M2: Config System tests.

-module(winn_m2_tests).
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

init_test() ->
    ?assertEqual(ok, winn_config:init()).

put_and_get_test() ->
    winn_config:init(),
    winn_config:put(database, pool_size, 10),
    ?assertEqual(10, winn_config:get(database, pool_size)).

get_missing_returns_nil_test() ->
    winn_config:init(),
    ?assertEqual(nil, winn_config:get(nonexistent, key)).

get_with_default_test() ->
    winn_config:init(),
    ?assertEqual(3000, winn_config:get(http, port, 3000)).

get_existing_ignores_default_test() ->
    winn_config:init(),
    winn_config:put(http, port, 4000),
    ?assertEqual(4000, winn_config:get(http, port, 3000)).

load_map_test() ->
    winn_config:init(),
    Config = #{database => #{pool_size => 5, timeout => 3000},
               http => #{port => 8080}},
    ?assertEqual(ok, winn_config:load(Config)),
    ?assertEqual(5, winn_config:get(database, pool_size)),
    ?assertEqual(3000, winn_config:get(database, timeout)),
    ?assertEqual(8080, winn_config:get(http, port)).

%% ── E2E test ────────────────────────────────────────────────────────────

e2e_config_get_test() ->
    winn_config:init(),
    winn_config:put(app, name, <<"myapp">>),
    Src = "module CfgTest\n  def run()\n    Config.get(:app, :name)\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"myapp">>, Mod:run()).

e2e_config_get_default_test() ->
    winn_config:init(),
    Src = "module CfgDef\n  def run()\n    Config.get(:missing, :key, 42)\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(42, Mod:run()).

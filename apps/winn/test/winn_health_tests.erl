-module(winn_health_tests).
-include_lib("eunit/include/eunit.hrl").

check_creates_tuple_test() ->
    {db, Fun} = winn_health:check(db, fun() -> ok end),
    ?assert(is_function(Fun, 0)).

run_checks_pass_test() ->
    Checks = [winn_health:check(db, fun() -> ok end)],
    %% We can't call liveness/readiness without a real conn,
    %% but we can verify check() works
    ?assertMatch({db, _}, hd(Checks)).

health_from_winn_test() ->
    Source = "module HealthTest\n  def run()\n    Health.check(:db, fn() => :ok end)\n  end\nend\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST} = winn_parser:parse(Tokens),
    Transformed = winn_transform:transform(AST),
    [CoreMod] = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    {db, Fun} = ModName:run(),
    ?assert(is_function(Fun, 0)).

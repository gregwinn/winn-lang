%% winn_r4_tests.erl — R4: Structured logging.

-module(winn_r4_tests).
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

info_returns_ok_test() ->
    ?assertEqual(ok, winn_logger:info(<<"test message">>)).

info_with_meta_returns_ok_test() ->
    ?assertEqual(ok, winn_logger:info(<<"test">>, #{user_id => 42})).

warn_returns_ok_test() ->
    ?assertEqual(ok, winn_logger:warn(<<"warning msg">>)).

error_returns_ok_test() ->
    ?assertEqual(ok, winn_logger:error(<<"error msg">>)).

debug_returns_ok_test() ->
    ?assertEqual(ok, winn_logger:debug(<<"debug msg">>)).

debug_with_meta_returns_ok_test() ->
    ?assertEqual(ok, winn_logger:debug(<<"checkpoint">>, #{step => 3})).

%% ── End-to-end test ─────────────────────────────────────────────────────

e2e_logger_info_test() ->
    Src = "module LogTest\n  def run()\n    Logger.info(\"hello log\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(ok, Mod:run()).

e2e_logger_with_meta_test() ->
    Src = "module LogMeta\n  def run()\n    Logger.info(\"event\", %{user_id: 42})\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(ok, Mod:run()).

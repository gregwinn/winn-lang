%% winn_r3_tests.erl — R3: DateTime functions.

-module(winn_r3_tests).
-include_lib("eunit/include/eunit.hrl").

compile_and_load(Source) ->
    {ok, Tokens, _} = winn_lexer:string(Source),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── Direct runtime tests ────────────────────────────────────────────────

now_returns_integer_test() ->
    Now = winn_runtime:'datetime.now'(),
    ?assert(is_integer(Now)),
    ?assert(Now > 1700000000).  %% sanity: after 2023

to_iso8601_test() ->
    %% 2024-01-01T00:00:00Z = 1704067200
    ?assertEqual(<<"2024-01-01T00:00:00Z">>,
                 winn_runtime:'datetime.to_iso8601'(1704067200)).

from_iso8601_test() ->
    ?assertEqual({ok, 1704067200},
                 winn_runtime:'datetime.from_iso8601'(<<"2024-01-01T00:00:00Z">>)).

roundtrip_test() ->
    Ts = 1704067200,
    Iso = winn_runtime:'datetime.to_iso8601'(Ts),
    ?assertEqual({ok, Ts}, winn_runtime:'datetime.from_iso8601'(Iso)).

diff_test() ->
    ?assertEqual(3600, winn_runtime:'datetime.diff'(1704070800, 1704067200)).

format_test() ->
    ?assertEqual(<<"2024-01-01">>,
                 winn_runtime:'datetime.format'(1704067200, <<"%Y-%m-%d">>)).

format_full_test() ->
    ?assertEqual(<<"2024-01-01 00:00:00">>,
                 winn_runtime:'datetime.format'(1704067200, <<"%Y-%m-%d %H:%M:%S">>)).

%% ── End-to-end tests ────────────────────────────────────────────────────

e2e_now_test() ->
    Src = "module DtNow\n  def run()\n    DateTime.now()\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assert(is_integer(Mod:run())).

e2e_to_iso_test() ->
    Src = "module DtIso\n  def run()\n    DateTime.to_iso8601(1704067200)\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"2024-01-01T00:00:00Z">>, Mod:run()).

e2e_diff_test() ->
    Src = "module DtDiff\n  def run()\n    DateTime.diff(1000, 500)\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(500, Mod:run()).

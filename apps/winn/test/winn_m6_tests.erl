%% winn_m6_tests.erl — M6: WebSocket tests.
%% Full WS tests require a running server; we test module structure,
%% URL parsing, and codegen integration.

-module(winn_m6_tests).
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

%% ── Module structure tests ──────────────────────────────────────────────

exports_test() ->
    Exports = winn_ws:module_info(exports),
    ?assert(lists:member({connect, 1}, Exports)),
    ?assert(lists:member({send, 2}, Exports)),
    ?assert(lists:member({recv, 1}, Exports)),
    ?assert(lists:member({recv, 2}, Exports)),
    ?assert(lists:member({close, 1}, Exports)).

%% ── E2E compilation tests ───────────────────────────────────────────────

e2e_ws_connect_compiles_test() ->
    Src = "module WsTest\n  def run()\n    WS.connect(\"ws://localhost:8080/ws\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assert(erlang:function_exported(Mod, run, 0)).

e2e_use_websocket_test() ->
    Src = "module WsHandler\n  use Winn.WebSocket\n\n  def on_connect(conn)\n    :ok\n  end\nend\n",
    {ok, Tokens, _} = winn_lexer:string(Src),
    {ok, AST} = winn_parser:parse(Tokens),
    [{module, _, 'WsHandler', Body}] = winn_transform:transform(AST),
    ?assertMatch({behaviour_attr, _, winn_ws_handler}, hd(Body)).

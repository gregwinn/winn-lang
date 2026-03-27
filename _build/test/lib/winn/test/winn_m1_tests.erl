%% winn_m1_tests.erl — M1: HTTP Client tests.
%% Tests the winn_http module directly and via end-to-end Winn compilation.
%% Note: E2E HTTP tests require network; direct tests verify module structure.

-module(winn_m1_tests).
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
    Exports = winn_http:module_info(exports),
    ?assert(lists:member({get, 1}, Exports)),
    ?assert(lists:member({post, 2}, Exports)),
    ?assert(lists:member({put, 2}, Exports)),
    ?assert(lists:member({patch, 2}, Exports)),
    ?assert(lists:member({delete, 1}, Exports)),
    ?assert(lists:member({request, 3}, Exports)).

%% ── Live HTTP test (GET to httpbin) ─────────────────────────────────────

get_httpbin_test() ->
    _ = application:ensure_all_started(hackney),
    case winn_http:get(<<"https://httpbin.org/get">>) of
        {ok, #{status := Status, body := Body, headers := Headers}} ->
            ?assertEqual(200, Status),
            ?assert(is_map(Body)),  %% JSON auto-decoded
            ?assert(is_map(Headers));
        {error, _Reason} ->
            %% Network may not be available in CI
            ok
    end.

%% ── E2E compilation test ────────────────────────────────────────────────

e2e_codegen_test() ->
    Src = "module HttpTest\n  def run()\n    HTTP.get(\"https://httpbin.org/get\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assert(erlang:function_exported(Mod, run, 0)).

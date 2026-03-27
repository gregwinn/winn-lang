%% winn_middleware_tests.erl — MI1: HTTP Middleware tests.

-module(winn_middleware_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Integration tests (live server with middleware) ─────────────────────

middleware_test_() ->
    {setup,
     fun start_server/0,
     fun stop_server/1,
     fun(_) ->
         [
          {"Middleware adds custom header",    fun test_custom_header/0},
          {"Auth middleware blocks no-token",  fun test_auth_blocks/0},
          {"Auth middleware passes with token", fun test_auth_passes/0},
          {"Middleware ordering is correct",    fun test_ordering/0}
         ]
     end}.

start_server() ->
    application:ensure_all_started(hackney),
    {ok, _} = winn_server:start(winn_mw_test_router, 19877),
    ok.

stop_server(_) ->
    winn_server:stop().

base_url() -> "http://localhost:19877".

test_custom_header() ->
    %% With auth header → should get through and have x-powered-by.
    {ok, Status, Headers, Ref} = hackney:get(
        base_url() ++ "/",
        [{<<"authorization">>, <<"Bearer test">>}]),
    {ok, _Body} = hackney:body(Ref),
    ?assertEqual(200, Status),
    HeaderMap = maps:from_list(Headers),
    ?assertEqual(<<"winn">>, maps:get(<<"x-powered-by">>, HeaderMap)).

test_auth_blocks() ->
    %% No auth header → middleware should short-circuit with 401.
    {ok, Status, _Headers, Ref} = hackney:get(base_url() ++ "/secret", []),
    {ok, Body} = hackney:body(Ref),
    ?assertEqual(401, Status),
    Decoded = jsone:decode(Body, [{object_format, map}]),
    ?assertEqual(<<"unauthorized">>, maps:get(<<"error">>, Decoded)).

test_auth_passes() ->
    %% With auth header → should reach the handler.
    {ok, Status, _Headers, Ref} = hackney:get(
        base_url() ++ "/secret",
        [{<<"authorization">>, <<"Bearer valid_token">>}]),
    {ok, Body} = hackney:body(Ref),
    ?assertEqual(200, Status),
    Decoded = jsone:decode(Body, [{object_format, map}]),
    ?assertEqual(<<"secret data">>, maps:get(<<"message">>, Decoded)).

test_ordering() ->
    %% add_header runs first, then check_auth.
    %% Even when auth fails (401), the x-powered-by header should be present
    %% because add_header runs before check_auth.
    {ok, 401, Headers, Ref} = hackney:get(base_url() ++ "/", []),
    {ok, _Body} = hackney:body(Ref),
    HeaderMap = maps:from_list(Headers),
    ?assertEqual(<<"winn">>, maps:get(<<"x-powered-by">>, HeaderMap)).

%% ── Unit test: build_chain without middleware ───────────────────────────

no_middleware_test() ->
    %% Router without middleware/0 should just call the handler directly.
    ?assert(not erlang:function_exported(winn_server_test_router, middleware, 0)).

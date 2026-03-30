%% winn_server_tests.erl — HTTP Server tests.
%% Tests route matching (unit), live server (integration), and Winn compilation (e2e).

-module(winn_server_tests).
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

%% ── Route matching unit tests ───────────────────────────────────────────

match_path_exact_test() ->
    ?assertEqual({ok, #{}}, winn_router:match_path(<<"/users">>, <<"/users">>)).

match_path_root_test() ->
    ?assertEqual({ok, #{}}, winn_router:match_path(<<"/">>, <<"/">>)).

match_path_param_test() ->
    ?assertEqual({ok, #{<<"id">> => <<"42">>}},
                 winn_router:match_path(<<"/users/:id">>, <<"/users/42">>)).

match_path_multi_param_test() ->
    ?assertEqual({ok, #{<<"uid">> => <<"1">>, <<"pid">> => <<"2">>}},
                 winn_router:match_path(<<"/users/:uid/posts/:pid">>, <<"/users/1/posts/2">>)).

match_path_no_match_test() ->
    ?assertEqual(nomatch, winn_router:match_path(<<"/users">>, <<"/posts">>)).

match_path_length_mismatch_test() ->
    ?assertEqual(nomatch, winn_router:match_path(<<"/users/:id">>, <<"/users">>)).

match_route_method_test() ->
    Routes = [{get, <<"/users">>, list_users}, {post, <<"/users">>, create_user}],
    ?assertMatch({ok, list_users, _}, winn_router:match_route(get, <<"/users">>, Routes)),
    ?assertMatch({ok, create_user, _}, winn_router:match_route(post, <<"/users">>, Routes)).

match_route_no_match_test() ->
    Routes = [{get, <<"/users">>, list_users}],
    ?assertEqual(nomatch, winn_router:match_route(delete, <<"/users">>, Routes)).

%% ── Live server integration tests ──────────────────────────────────────

server_integration_test_() ->
    {setup,
     fun start_server/0,
     fun stop_server/1,
     fun(_) ->
         [
          {"GET / returns JSON welcome",  fun test_get_index/0},
          {"GET /users/:id extracts id",  fun test_get_user/0},
          {"POST /users with JSON body",  fun test_post_user/0},
          {"GET /echo?name=x query param", fun test_query_param/0},
          {"GET /nonexistent returns 404", fun test_not_found/0}
         ]
     end}.

start_server() ->
    application:ensure_all_started(hackney),
    {ok, _} = winn_server:start(winn_server_test_router, 19876),
    ok.

stop_server(_) ->
    winn_server:stop().

base_url() -> "http://localhost:19876".

test_get_index() ->
    {ok, Status, _Headers, Ref} = hackney:get(base_url() ++ "/", []),
    {ok, Body} = hackney:body(Ref),
    ?assertEqual(200, Status),
    Decoded = jsone:decode(Body, [{object_format, map}]),
    ?assertEqual(<<"welcome">>, maps:get(<<"message">>, Decoded)).

test_get_user() ->
    {ok, Status, _Headers, Ref} = hackney:get(base_url() ++ "/users/42", []),
    {ok, Body} = hackney:body(Ref),
    ?assertEqual(200, Status),
    Decoded = jsone:decode(Body, [{object_format, map}]),
    ?assertEqual(<<"42">>, maps:get(<<"id">>, Decoded)).

test_post_user() ->
    ReqBody = jsone:encode(#{<<"name">> => <<"Alice">>}),
    {ok, Status, _Headers, Ref} = hackney:post(
        base_url() ++ "/users",
        [{<<"content-type">>, <<"application/json">>}],
        ReqBody, []),
    {ok, Body} = hackney:body(Ref),
    ?assertEqual(201, Status),
    Decoded = jsone:decode(Body, [{object_format, map}]),
    ?assertEqual(<<"Alice">>, maps:get(<<"name">>, Decoded)).

test_query_param() ->
    {ok, Status, _Headers, Ref} = hackney:get(base_url() ++ "/echo?name=bob", []),
    {ok, Body} = hackney:body(Ref),
    ?assertEqual(200, Status),
    Decoded = jsone:decode(Body, [{object_format, map}]),
    ?assertEqual(<<"bob">>, maps:get(<<"name">>, Decoded)).

test_not_found() ->
    {ok, Status, _Headers, Ref} = hackney:get(base_url() ++ "/nonexistent", []),
    {ok, _Body} = hackney:body(Ref),
    ?assertEqual(404, Status).

%% ── E2E Winn compilation test ───────────────────────────────────────────

e2e_router_compiles_test() ->
    Src = "module TestRouter\n"
          "  use Winn.Router\n\n"
          "  def routes()\n"
          "    [{:get, \"/\", :index}]\n"
          "  end\n\n"
          "  def index(conn)\n"
          "    Server.json(conn, %{status: true})\n"
          "  end\n"
          "end\n",
    Mod = compile_and_load(Src),
    ?assert(erlang:function_exported(Mod, routes, 0)),
    ?assert(erlang:function_exported(Mod, index, 1)).

e2e_use_router_behaviour_test() ->
    Src = "module ApiRouter\n"
          "  use Winn.Router\n\n"
          "  def routes()\n"
          "    []\n"
          "  end\n"
          "end\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, AST} = winn_parser:parse(Tokens),
    [{module, _, 'ApiRouter', Body}] = winn_transform:transform(AST),
    ?assertMatch({behaviour_attr, _, winn_router}, hd(Body)).

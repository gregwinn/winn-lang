%% winn_cookie_auth_tests — integration tests for the cookie auth strategy and
%% double-submit CSRF, driving the built-in `[:auth]` middleware over a live
%% server. Bearer mode is exercised too, to confirm it still works.
-module(winn_cookie_auth_tests).
-include_lib("eunit/include/eunit.hrl").

cookie_auth_test_() ->
    {setup, fun start/0, fun stop/1,
     fun(_) ->
         [
          {"bearer mode still authenticates",   fun bearer_ok/0},
          {"cookie auth passes with JWT cookie", fun cookie_ok/0},
          {"cookie auth missing cookie -> 401",  fun cookie_missing/0},
          {"unsafe POST with matching CSRF ok",  fun csrf_ok/0},
          {"unsafe POST with bad CSRF -> 403",   fun csrf_bad/0},
          {"write_session sets auth cookies",    fun login_sets_cookies/0}
         ]
     end}.

start() ->
    application:ensure_all_started(hackney),
    winn_config:init(),
    {ok, _} = winn_server:start(winn_cookie_test_router, 19878),
    ok.

stop(_) ->
    winn_server:stop().

url(P) -> "http://localhost:19878" ++ P.

%% A valid access JWT for the router's secret.
jwt() ->
    Exp = os:system_time(second) + 3600,
    winn_jwt:sign(#{<<"user_id">> => 1, <<"exp">> => Exp}, <<"test_secret">>).

status(Method, Path, Headers) ->
    {ok, Status, _RespHeaders, Ref} =
        hackney:request(Method, url(Path), Headers, <<>>, []),
    {ok, _Body} = hackney:body(Ref),
    Status.

bearer_ok() ->
    winn_config:put(test, strategy, bearer),
    ?assertEqual(200, status(get, "/me",
        [{<<"authorization">>, <<"Bearer ", (jwt())/binary>>}])).

cookie_ok() ->
    winn_config:put(test, strategy, cookie),
    ?assertEqual(200, status(get, "/me",
        [{<<"cookie">>, <<"access_token=", (jwt())/binary>>}])).

cookie_missing() ->
    winn_config:put(test, strategy, cookie),
    ?assertEqual(401, status(get, "/me", [])).

csrf_ok() ->
    winn_config:put(test, strategy, cookie),
    Cookie = <<"access_token=", (jwt())/binary, "; csrf=tok123">>,
    ?assertEqual(200, status(post, "/change",
        [{<<"cookie">>, Cookie}, {<<"x-csrf-token">>, <<"tok123">>}])).

csrf_bad() ->
    winn_config:put(test, strategy, cookie),
    Cookie = <<"access_token=", (jwt())/binary, "; csrf=tok123">>,
    %% Valid session cookie but a forged/mismatched CSRF token.
    ?assertEqual(403, status(post, "/change",
        [{<<"cookie">>, Cookie}, {<<"x-csrf-token">>, <<"WRONG">>}])).

login_sets_cookies() ->
    winn_config:put(test, strategy, cookie),
    {ok, 200, Headers, Ref} = hackney:request(post, url("/login"), [], <<>>, []),
    {ok, _} = hackney:body(Ref),
    SetCookies = iolist_to_binary(
        [V || {K, V} <- Headers, string:lowercase(binary_to_list(K)) =:= "set-cookie"]),
    ?assertNotEqual(nomatch, binary:match(SetCookies, <<"access_token=AAA">>)),
    ?assertNotEqual(nomatch, binary:match(SetCookies, <<"csrf=">>)),
    %% The access-token cookie must be HttpOnly.
    ?assertNotEqual(nomatch, binary:match(SetCookies, <<"HttpOnly">>)).

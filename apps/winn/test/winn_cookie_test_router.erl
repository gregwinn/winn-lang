%% Test router for winn_cookie_auth_tests — exercises the built-in `[:auth]`
%% middleware in both `:bearer` and `:cookie` strategies. The strategy is read
%% from config per request, so one router serves both modes across tests.
-module(winn_cookie_test_router).
-export([routes/0, middleware/0, auth_config/0, login/1, me/1, change/1]).

routes() ->
    [
        {post, <<"/login">>,  login},
        {get,  <<"/me">>,     me},
        {post, <<"/change">>, change}
    ].

middleware() -> [auth].

auth_config() ->
    #{strategy => winn_config:get(test, strategy, bearer),
      secret   => <<"test_secret">>,
      exclude  => [<<"/login">>]}.

%% Cookie-mode login: write the auth cookies, then respond.
login(Conn) ->
    Conn2 = winn_auth:write_session(Conn, #{access_token  => <<"AAA">>,
                                            refresh_token => <<"BBB">>}),
    winn_server:json(Conn2, #{ok => true}).

me(Conn) ->
    winn_server:json(Conn, #{ok => true}).

change(Conn) ->
    winn_server:json(Conn, #{changed => true}).

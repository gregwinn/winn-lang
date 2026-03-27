%% Test router with middleware for winn_middleware_tests.
-module(winn_mw_test_router).
-export([routes/0, middleware/0]).
-export([add_header/2, check_auth/2]).
-export([index/1, secret/1]).

routes() ->
    [
        {get, <<"/">>,       index},
        {get, <<"/secret">>, secret}
    ].

middleware() ->
    [add_header, check_auth].

%% Middleware 1: adds a custom response header.
add_header(Conn, Next) ->
    Conn2 = winn_server:set_header(Conn, <<"x-powered-by">>, <<"winn">>),
    Next(Conn2).

%% Middleware 2: checks for authorization header; short-circuits if missing.
check_auth(Conn, Next) ->
    case winn_server:header(Conn, <<"authorization">>) of
        nil ->
            winn_server:json(Conn, #{error => <<"unauthorized">>}, 401);
        _Token ->
            Next(Conn)
    end.

index(Conn) ->
    winn_server:json(Conn, #{message => <<"public">>}).

secret(Conn) ->
    winn_server:json(Conn, #{message => <<"secret data">>}).

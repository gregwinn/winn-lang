%% Test router module used by winn_server_tests.
-module(winn_server_test_router).
-export([routes/0, index/1, get_user/1, create_user/1, echo_query/1]).

routes() ->
    [
        {get,  <<"/">>,          index},
        {get,  <<"/users/:id">>, get_user},
        {post, <<"/users">>,     create_user},
        {get,  <<"/echo">>,      echo_query}
    ].

index(Conn) ->
    winn_server:json(Conn, #{message => <<"welcome">>}).

get_user(Conn) ->
    Id = winn_server:path_param(Conn, <<"id">>),
    winn_server:json(Conn, #{id => Id}).

create_user(Conn) ->
    Params = winn_server:body_params(Conn),
    winn_server:json(Conn, Params, 201).

echo_query(Conn) ->
    Name = winn_server:query_param(Conn, <<"name">>),
    winn_server:json(Conn, #{name => Name}).

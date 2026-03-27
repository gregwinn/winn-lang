%% winn_server.erl
%% HTTP server runtime for Winn programs.
%%
%% Server.start(RouterModule, Port) -> {:ok, pid}
%% Server.stop()                    -> ok
%%
%% Response helpers:
%%   Server.json(conn, data)            -> conn (200)
%%   Server.json(conn, data, status)    -> conn
%%   Server.text(conn, body)            -> conn (200)
%%   Server.text(conn, body, status)    -> conn
%%   Server.send(conn, status, headers, body) -> conn
%%
%% Request accessors:
%%   Server.body_params(conn)       -> map
%%   Server.path_param(conn, key)   -> binary | nil
%%   Server.query_param(conn, key)  -> binary | nil
%%   Server.header(conn, name)      -> binary | nil
%%   Server.method(conn)            -> binary
%%   Server.path(conn)              -> binary

-module(winn_server).
-export([start/2, stop/0]).
-export([json/2, json/3, text/2, text/3, send/4]).
-export([body_params/1, path_param/2, query_param/2, header/2]).
-export([method/1, path/1]).
-export([set_header/3]).

-define(LISTENER, winn_http_listener).

%% ── Server lifecycle ────────────────────────────────────────────────────

start(RouterModule, Port) when is_atom(RouterModule), is_integer(Port) ->
    application:ensure_all_started(cowboy),
    Dispatch = cowboy_router:compile([
        {'_', [{'_', winn_router, #{router => RouterModule}}]}
    ]),
    cowboy:start_clear(?LISTENER, [{port, Port}], #{
        env => #{dispatch => Dispatch}
    }).

stop() ->
    cowboy:stop_listener(?LISTENER).

%% ── Response helpers ────────────────────────────────────────────────────

json(Conn, Data) ->
    json(Conn, Data, 200).

json(#{req := Req0} = Conn, Data, Status) ->
    Body = jsone:encode(prepare_json(Data)),
    Req1 = cowboy_req:reply(Status,
        #{<<"content-type">> => <<"application/json">>},
        Body, Req0),
    Conn#{req := Req1}.

text(Conn, Body) ->
    text(Conn, Body, 200).

text(#{req := Req0} = Conn, Body, Status) when is_binary(Body) ->
    Req1 = cowboy_req:reply(Status,
        #{<<"content-type">> => <<"text/plain">>},
        Body, Req0),
    Conn#{req := Req1}.

send(#{req := Req0} = Conn, Status, Headers, Body) when is_integer(Status), is_map(Headers), is_binary(Body) ->
    Req1 = cowboy_req:reply(Status, Headers, Body, Req0),
    Conn#{req := Req1}.

%% ── Request accessors ───────────────────────────────────────────────────

body_params(#{req := Req0, body_params := nil}) ->
    case cowboy_req:read_body(Req0) of
        {ok, RawBody, _Req1} ->
            try jsone:decode(RawBody, [{object_format, map}, {keys, atom}])
            catch _:_ -> #{}
            end;
        _ ->
            #{}
    end;
body_params(#{body_params := Params}) when is_map(Params) ->
    Params;
body_params(_) ->
    #{}.

path_param(#{path_params := Params}, Key) when is_binary(Key) ->
    maps:get(Key, Params, nil);
path_param(_, _) ->
    nil.

query_param(#{query_params := Params}, Key) when is_binary(Key) ->
    maps:get(Key, Params, nil);
query_param(_, _) ->
    nil.

header(#{req := Req}, Name) when is_binary(Name) ->
    case cowboy_req:header(Name, Req) of
        undefined -> nil;
        Val       -> Val
    end;
header(_, _) ->
    nil.

method(#{method := M}) -> M.
path(#{path := P})     -> P.

%% Set a response header on the conn. Headers are applied when the response is sent.
%% Stores pending headers in the conn map; json/text/send will include them.
set_header(#{req := Req0} = Conn, Name, Value) when is_binary(Name), is_binary(Value) ->
    Req1 = cowboy_req:set_resp_header(Name, Value, Req0),
    Conn#{req := Req1}.

%% ── JSON encoding helpers ───────────────────────────────────────────────

prepare_json(Data) when is_map(Data) ->
    maps:fold(fun(K, V, Acc) ->
        BinK = if is_atom(K)   -> atom_to_binary(K, utf8);
                  is_binary(K) -> K;
                  true         -> list_to_binary(io_lib:format("~p", [K]))
               end,
        maps:put(BinK, prepare_json(V), Acc)
    end, #{}, Data);
prepare_json(List) when is_list(List) ->
    [prepare_json(E) || E <- List];
prepare_json(A) when is_atom(A), A =/= true, A =/= false, A =/= null, A =/= nil ->
    atom_to_binary(A, utf8);
prepare_json(nil) ->
    null;
prepare_json(Other) ->
    Other.

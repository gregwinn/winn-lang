%% winn_cors.erl
%% Built-in CORS middleware for Winn HTTP servers.

-module(winn_cors).
-export([middleware/3, default_config/0]).

-define(DEFAULT_ORIGINS, <<"*">>).
-define(DEFAULT_METHODS, <<"GET, POST, PUT, PATCH, DELETE, OPTIONS">>).
-define(DEFAULT_HEADERS, <<"Content-Type, Authorization, Accept">>).
-define(DEFAULT_MAX_AGE, <<"86400">>).

%% ── Middleware ──────────────────────────────────────────────────────────────

middleware(Conn, Next, Config) ->
    Origins = get_config(origins, Config, ?DEFAULT_ORIGINS),
    Methods = get_config(methods, Config, ?DEFAULT_METHODS),
    Headers = get_config(headers, Config, ?DEFAULT_HEADERS),
    MaxAge  = get_config(max_age, Config, ?DEFAULT_MAX_AGE),

    %% Add CORS headers to the response
    Req = maps:get(req, Conn),
    Req1 = cowboy_req:set_resp_header(<<"access-control-allow-origin">>, Origins, Req),
    Req2 = cowboy_req:set_resp_header(<<"access-control-allow-methods">>, Methods, Req1),
    Req3 = cowboy_req:set_resp_header(<<"access-control-allow-headers">>, Headers, Req2),
    Req4 = cowboy_req:set_resp_header(<<"access-control-max-age">>, MaxAge, Req3),

    Conn2 = Conn#{req => Req4},

    %% Handle preflight OPTIONS requests
    case maps:get(method, Conn) of
        <<"OPTIONS">> ->
            %% Return 204 No Content for preflight
            Req5 = cowboy_req:reply(204, #{}, <<>>, Req4),
            Conn2#{req => Req5};
        _ ->
            Next(Conn2)
    end.

%% ── Config ──────────────────────────────────────────────────────────────────

default_config() ->
    #{origins => ?DEFAULT_ORIGINS,
      methods => ?DEFAULT_METHODS,
      headers => ?DEFAULT_HEADERS,
      max_age => ?DEFAULT_MAX_AGE}.

%% ── Internal ────────────────────────────────────────────────────────────────

get_config(Key, Config, Default) ->
    case maps:get(Key, Config, undefined) of
        undefined -> Default;
        Value when is_list(Value) ->
            %% Convert list of strings to comma-separated binary
            list_to_binary(lists:join(", ", [to_bin(V) || V <- Value]));
        Value when is_binary(Value) -> Value;
        Value when is_integer(Value) -> integer_to_binary(Value);
        Value when is_atom(Value) -> atom_to_binary(Value, utf8)
    end.

to_bin(V) when is_binary(V) -> V;
to_bin(V) when is_list(V)   -> list_to_binary(V);
to_bin(V) when is_atom(V)   -> atom_to_binary(V, utf8).

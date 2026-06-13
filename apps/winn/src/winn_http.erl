%% winn_http.erl
%% M1 — HTTP Client for Winn programs.
%%
%% HTTP.get(url)               -> {:ok, %{status, body, headers}}
%% HTTP.post(url, body_map)    -> {:ok, %{status, body, headers}}
%% HTTP.put(url, body_map)     -> {:ok, %{status, body, headers}}
%% HTTP.patch(url, body_map)   -> {:ok, %{status, body, headers}}
%% HTTP.delete(url)            -> {:ok, %{status, body, headers}}
%% HTTP.request(method, url, body_or_nil) -> {:ok, %{status, body, headers}}

-module(winn_http).
-export([get/1, get/2, post/2, post/3, put/2, put/3, patch/2, patch/3,
         delete/1, delete/2, request/3, request/4]).

%% Each verb has an optional trailing Opts map (Winn: HTTP.post(url, body, %{...})):
%%   timeout / recv_timeout (ms, default 30000), connect_timeout (ms, default
%%   15000), follow_redirect (default true).
get(Url) when is_binary(Url) ->
    request(get, Url, nil, #{}).
get(Url, Opts) when is_binary(Url), is_map(Opts) ->
    request(get, Url, nil, Opts).

post(Url, Body) when is_binary(Url) ->
    request(post, Url, Body, #{}).
post(Url, Body, Opts) when is_binary(Url), is_map(Opts) ->
    request(post, Url, Body, Opts).

put(Url, Body) when is_binary(Url) ->
    request(put, Url, Body, #{}).
put(Url, Body, Opts) when is_binary(Url), is_map(Opts) ->
    request(put, Url, Body, Opts).

patch(Url, Body) when is_binary(Url) ->
    request(patch, Url, Body, #{}).
patch(Url, Body, Opts) when is_binary(Url), is_map(Opts) ->
    request(patch, Url, Body, Opts).

delete(Url) when is_binary(Url) ->
    request(delete, Url, nil, #{}).
delete(Url, Opts) when is_binary(Url), is_map(Opts) ->
    request(delete, Url, nil, Opts).

request(Method, Url, Body) ->
    request(Method, Url, Body, #{}).

request(Method, Url, Body, Opts) ->
    ensure_started(),
    {ReqHeaders, ReqBody} = encode_body(Body),
    case hackney:request(Method, Url, ReqHeaders, ReqBody, hackney_opts(Opts)) of
        {ok, StatusCode, RespHeaders, ClientRef} ->
            case hackney:body(ClientRef) of
                {ok, RespBody} ->
                    DecodedBody = maybe_decode_json(RespBody, RespHeaders),
                    HeaderMap = headers_to_map(RespHeaders),
                    {ok, #{status => StatusCode,
                           body => DecodedBody,
                           headers => HeaderMap}};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, StatusCode, RespHeaders} ->
            HeaderMap = headers_to_map(RespHeaders),
            {ok, #{status => StatusCode,
                   body => nil,
                   headers => HeaderMap}};
        {error, Reason} ->
            {error, Reason}
    end.

%% ── Internal helpers ────────────────────────────────────────────────────

%% Per-call options -> hackney options. Defaults are generous because hackney's
%% own defaults (8s connect / 5s recv) are too aggressive for slower APIs; all
%% are overridable per request. `timeout` is an alias for the receive timeout.
hackney_opts(Opts) when is_map(Opts) ->
    Recv = maps:get(recv_timeout, Opts, maps:get(timeout, Opts, 30000)),
    Conn = maps:get(connect_timeout, Opts, 15000),
    Redirect = maps:get(follow_redirect, Opts, true),
    [{follow_redirect, Redirect}, {connect_timeout, Conn}, {recv_timeout, Recv}];
hackney_opts(_) ->
    [{follow_redirect, true}, {connect_timeout, 15000}, {recv_timeout, 30000}].

ensure_started() ->
    _ = application:ensure_all_started(hackney),
    ok.

encode_body(nil) ->
    {[], <<>>};
encode_body(Body) when is_map(Body) ->
    Json = jsone:encode(encode_map_keys(Body)),
    {[{<<"Content-Type">>, <<"application/json">>}], Json};
encode_body(Body) when is_binary(Body) ->
    {[{<<"Content-Type">>, <<"application/octet-stream">>}], Body}.

encode_map_keys(Map) when is_map(Map) ->
    maps:fold(fun(K, V, Acc) ->
        BinK = if is_atom(K) -> atom_to_binary(K, utf8);
                  is_binary(K) -> K;
                  true -> list_to_binary(io_lib:format("~p", [K]))
               end,
        maps:put(BinK, encode_value(V), Acc)
    end, #{}, Map);
encode_map_keys(Other) -> Other.

encode_value(M) when is_map(M) -> encode_map_keys(M);
encode_value(L) when is_list(L) -> [encode_value(E) || E <- L];
encode_value(A) when is_atom(A) -> atom_to_binary(A, utf8);
encode_value(Other) -> Other.

maybe_decode_json(Body, Headers) ->
    case is_json_content_type(Headers) of
        true ->
            try jsone:decode(Body, [{object_format, map}, {keys, atom}])
            catch _:_ -> Body
            end;
        false ->
            Body
    end.

is_json_content_type([]) -> false;
is_json_content_type([{Key, Val} | Rest]) ->
    case string:lowercase(Key) of
        <<"content-type">> ->
            binary:match(string:lowercase(Val), <<"json">>) =/= nomatch;
        _ ->
            is_json_content_type(Rest)
    end.

headers_to_map(Headers) ->
    maps:from_list([{string:lowercase(K), V} || {K, V} <- Headers]).

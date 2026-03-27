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
-export([get/1, post/2, put/2, patch/2, delete/1, request/3]).

get(Url) when is_binary(Url) ->
    request(get, Url, nil).

post(Url, Body) when is_binary(Url) ->
    request(post, Url, Body).

put(Url, Body) when is_binary(Url) ->
    request(put, Url, Body).

patch(Url, Body) when is_binary(Url) ->
    request(patch, Url, Body).

delete(Url) when is_binary(Url) ->
    request(delete, Url, nil).

request(Method, Url, Body) ->
    ensure_started(),
    {ReqHeaders, ReqBody} = encode_body(Body),
    case hackney:request(Method, Url, ReqHeaders, ReqBody, [{follow_redirect, true}]) of
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

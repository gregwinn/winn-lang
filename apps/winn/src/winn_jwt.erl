%% winn_jwt.erl
%% M5 — JWT (JSON Web Tokens) for Winn programs.
%%
%% Pure Erlang HS256 implementation — no external deps.
%%
%% JWT.sign(claims_map, secret_binary)    -> token_binary
%% JWT.verify(token_binary, secret_binary) -> {:ok, claims_map} | {:error, reason}

-module(winn_jwt).
-export([sign/2, verify/2]).

%% Sign a claims map with HS256, returns a JWT binary.
sign(Claims, Secret) when is_map(Claims), is_binary(Secret) ->
    Header = #{<<"alg">> => <<"HS256">>, <<"typ">> => <<"JWT">>},
    HeaderB64  = b64url_encode(json_encode(Header)),
    ClaimsB64  = b64url_encode(json_encode(encode_claims(Claims))),
    Payload    = <<HeaderB64/binary, $., ClaimsB64/binary>>,
    Signature  = b64url_encode(hmac_sha256(Secret, Payload)),
    <<Payload/binary, $., Signature/binary>>.

%% Verify a JWT token. Returns {ok, ClaimsMap} or {error, Reason}.
verify(Token, Secret) when is_binary(Token), is_binary(Secret) ->
    case binary:split(Token, <<".">>, [global]) of
        [HeaderB64, ClaimsB64, SigB64] ->
            Payload = <<HeaderB64/binary, $., ClaimsB64/binary>>,
            ExpectedSig = b64url_encode(hmac_sha256(Secret, Payload)),
            case constant_time_compare(SigB64, ExpectedSig) of
                true ->
                    try
                        ClaimsJson = b64url_decode(ClaimsB64),
                        Claims = json_decode(ClaimsJson),
                        case check_expiry(Claims) of
                            ok      -> {ok, Claims};
                            expired -> {error, expired}
                        end
                    catch _:_ ->
                        {error, invalid_token}
                    end;
                false ->
                    {error, invalid_signature}
            end;
        _ ->
            {error, malformed_token}
    end.

%% ── Internal helpers ────────────────────────────────────────────────────

hmac_sha256(Key, Data) ->
    crypto:mac(hmac, sha256, Key, Data).

b64url_encode(Bin) ->
    B64 = base64:encode(Bin),
    %% Replace +/ with -_, strip trailing =
    Replaced = binary:replace(
        binary:replace(B64, <<"+">>, <<"-">>, [global]),
        <<"/">>, <<"_">>, [global]),
    strip_padding(Replaced).

strip_padding(Bin) ->
    case binary:last(Bin) of
        $= -> strip_padding(binary:part(Bin, 0, byte_size(Bin) - 1));
        _  -> Bin
    end.

b64url_decode(Bin) ->
    %% Restore standard base64
    Replaced = binary:replace(
        binary:replace(Bin, <<"-">>, <<"+">>, [global]),
        <<"_">>, <<"/">>, [global]),
    %% Add padding
    Padded = case byte_size(Replaced) rem 4 of
        0 -> Replaced;
        2 -> <<Replaced/binary, "==">>;
        3 -> <<Replaced/binary, "=">>;
        _ -> Replaced
    end,
    base64:decode(Padded).

%% Constant-time comparison to prevent timing attacks.
constant_time_compare(A, B) when byte_size(A) =/= byte_size(B) -> false;
constant_time_compare(A, B) ->
    constant_time_compare(A, B, 0).
constant_time_compare(<<>>, <<>>, 0) -> true;
constant_time_compare(<<>>, <<>>, _) -> false;
constant_time_compare(<<X, RestA/binary>>, <<Y, RestB/binary>>, Acc) ->
    constant_time_compare(RestA, RestB, Acc bor (X bxor Y)).

check_expiry(Claims) when is_map(Claims) ->
    case maps:find(<<"exp">>, Claims) of
        {ok, Exp} when is_integer(Exp) ->
            Now = os:system_time(second),
            case Now < Exp of
                true  -> ok;
                false -> expired
            end;
        _ ->
            ok  %% No exp claim — token doesn't expire
    end.

%% Encode claims: convert atom keys to binaries.
encode_claims(Map) ->
    maps:fold(fun(K, V, Acc) ->
        BinK = if is_atom(K) -> atom_to_binary(K, utf8);
                  is_binary(K) -> K
               end,
        maps:put(BinK, encode_val(V), Acc)
    end, #{}, Map).

encode_val(A) when is_atom(A) -> atom_to_binary(A, utf8);
encode_val(M) when is_map(M) -> encode_claims(M);
encode_val(L) when is_list(L) -> [encode_val(E) || E <- L];
encode_val(Other) -> Other.

%% Minimal JSON encoder for JWT payloads.
json_encode(Map) when is_map(Map) ->
    Pairs = maps:fold(fun(K, V, Acc) ->
        [[$", escape(K), $", $:, json_enc_val(V)] | Acc]
    end, [], Map),
    iolist_to_binary([${, lists:join($,, Pairs), $}]).

json_enc_val(Bin) when is_binary(Bin) -> [$", escape(Bin), $"];
json_enc_val(Int) when is_integer(Int) -> integer_to_list(Int);
json_enc_val(Flt) when is_float(Flt) -> float_to_list(Flt, [{decimals, 10}, compact]);
json_enc_val(true) -> <<"true">>;
json_enc_val(false) -> <<"false">>;
json_enc_val(null) -> <<"null">>;
json_enc_val(List) when is_list(List) ->
    [$[, lists:join($,, [json_enc_val(E) || E <- List]), $]];
json_enc_val(Map) when is_map(Map) -> json_encode(Map).

escape(Bin) when is_binary(Bin) -> escape_chars(binary_to_list(Bin)).
escape_chars([]) -> [];
escape_chars([$" | T])  -> [$\\, $" | escape_chars(T)];
escape_chars([$\\ | T]) -> [$\\, $\\ | escape_chars(T)];
escape_chars([$\n | T]) -> [$\\, $n | escape_chars(T)];
escape_chars([C | T])   -> [C | escape_chars(T)].

%% Minimal JSON decoder — handles objects, arrays, strings, numbers, booleans, null.
json_decode(Bin) when is_binary(Bin) ->
    {Val, _Rest} = json_parse(binary_to_list(Bin)),
    Val.

json_parse([${ | Rest]) -> json_parse_object(skip_ws(Rest), #{});
json_parse([$[ | Rest]) -> json_parse_array(skip_ws(Rest), []);
json_parse([$" | Rest]) -> json_parse_string(Rest, []);
json_parse([$t,$r,$u,$e | Rest]) -> {true, Rest};
json_parse([$f,$a,$l,$s,$e | Rest]) -> {false, Rest};
json_parse([$n,$u,$l,$l | Rest]) -> {null, Rest};
json_parse([$- | Rest]) ->
    {Num, Rest2} = json_parse_number(Rest, []),
    {-Num, Rest2};
json_parse([C | _] = S) when C >= $0, C =< $9 ->
    json_parse_number(S, []).

json_parse_object([$} | Rest], Acc) -> {Acc, Rest};
json_parse_object([$, | Rest], Acc) -> json_parse_object(skip_ws(Rest), Acc);
json_parse_object([$" | Rest], Acc) ->
    {Key, Rest2} = json_parse_string(Rest, []),
    [$: | Rest3] = skip_ws(Rest2),
    {Val, Rest4} = json_parse(skip_ws(Rest3)),
    json_parse_object(skip_ws(Rest4), maps:put(Key, Val, Acc)).

json_parse_array([$] | Rest], Acc) -> {lists:reverse(Acc), Rest};
json_parse_array([$, | Rest], Acc) -> json_parse_array(skip_ws(Rest), Acc);
json_parse_array(S, Acc) ->
    {Val, Rest} = json_parse(S),
    json_parse_array(skip_ws(Rest), [Val | Acc]).

json_parse_string([$" | Rest], Acc) -> {list_to_binary(lists:reverse(Acc)), Rest};
json_parse_string([$\\, $" | Rest], Acc) -> json_parse_string(Rest, [$" | Acc]);
json_parse_string([$\\, $\\ | Rest], Acc) -> json_parse_string(Rest, [$\\ | Acc]);
json_parse_string([$\\, $n | Rest], Acc) -> json_parse_string(Rest, [$\n | Acc]);
json_parse_string([C | Rest], Acc) -> json_parse_string(Rest, [C | Acc]).

json_parse_number([C | Rest], Acc) when C >= $0, C =< $9 ->
    json_parse_number(Rest, [C | Acc]);
json_parse_number([$. | Rest], Acc) ->
    json_parse_float(Rest, [$. | Acc]);
json_parse_number(Rest, Acc) ->
    {list_to_integer(lists:reverse(Acc)), Rest}.

json_parse_float([C | Rest], Acc) when C >= $0, C =< $9 ->
    json_parse_float(Rest, [C | Acc]);
json_parse_float(Rest, Acc) ->
    {list_to_float(lists:reverse(Acc)), Rest}.

skip_ws([$\s | R]) -> skip_ws(R);
skip_ws([$\t | R]) -> skip_ws(R);
skip_ws([$\n | R]) -> skip_ws(R);
skip_ws([$\r | R]) -> skip_ws(R);
skip_ws(R) -> R.

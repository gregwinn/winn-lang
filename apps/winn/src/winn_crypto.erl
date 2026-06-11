%% winn_crypto.erl
%% R5 — Crypto and hashing functions for Winn programs.
%%
%% Crypto.hash(:sha256, "data")
%% Crypto.hmac(:sha256, "secret", "data")
%% Crypto.random_bytes(32)
%% Crypto.base64_encode(bytes)
%% Crypto.base64_decode(string)
%% Crypto.hash_password("secret")          -> PHC-style hash string
%% Crypto.verify_password("secret", hash)  -> true | false

-module(winn_crypto).
-export([hash/2, hmac/3, random_bytes/1,
         base64_encode/1, base64_decode/1,
         hash_password/1, verify_password/2]).

%% Password hashing parameters. PBKDF2-HMAC-SHA256; iteration count follows the
%% OWASP recommendation for this algorithm. The algorithm + iterations are stored
%% in the hash string itself, so these can be raised over time (and bcrypt/argon2
%% added) without breaking verification of existing hashes.
-define(PW_ITERATIONS, 600000).
-define(PW_KEYLEN, 32).
-define(PW_SALT_BYTES, 16).

%% hash(Algorithm, Data) -> hex-encoded binary
%% Algorithm: sha256 | sha384 | sha512 | sha | md5
hash(Algo, Data) when is_atom(Algo), is_binary(Data) ->
    Digest = crypto:hash(normalize_algo(Algo), Data),
    bin_to_hex(Digest).

%% hmac(Algorithm, Key, Data) -> hex-encoded binary
hmac(Algo, Key, Data) when is_atom(Algo), is_binary(Key), is_binary(Data) ->
    Digest = crypto:mac(hmac, normalize_algo(Algo), Key, Data),
    bin_to_hex(Digest).

%% random_bytes(N) -> N random bytes as binary
random_bytes(N) when is_integer(N), N > 0 ->
    crypto:strong_rand_bytes(N).

%% base64_encode(Bin) -> base64-encoded binary string
base64_encode(Bin) when is_binary(Bin) ->
    base64:encode(Bin).

%% base64_decode(Bin) -> decoded binary
base64_decode(Bin) when is_binary(Bin) ->
    base64:decode(Bin).

%% hash_password(Password) -> PHC-style hash binary
%% "$pbkdf2-sha256$i=<iterations>$<salt_b64>$<hash_b64>"
%% A fresh random salt is generated per call, so hashing the same password twice
%% yields different strings.
hash_password(Password) when is_binary(Password) ->
    Salt = crypto:strong_rand_bytes(?PW_SALT_BYTES),
    Iter = ?PW_ITERATIONS,
    Derived = crypto:pbkdf2_hmac(sha256, Password, Salt, Iter, ?PW_KEYLEN),
    iolist_to_binary([<<"$pbkdf2-sha256$i=">>, integer_to_binary(Iter),
                      $$, base64:encode(Salt),
                      $$, base64:encode(Derived)]).

%% verify_password(Password, Encoded) -> true | false
%% Recomputes the derivation with the salt + iterations embedded in Encoded and
%% compares constant-time. Returns false (never crashes) on a malformed hash or
%% non-binary input, so it is safe to call on untrusted/stored data.
verify_password(Password, Encoded) when is_binary(Password), is_binary(Encoded) ->
    case parse_phc(Encoded) of
        {ok, Iter, Salt, Expected} ->
            Derived = crypto:pbkdf2_hmac(sha256, Password, Salt, Iter, byte_size(Expected)),
            constant_time_compare(Derived, Expected);
        error ->
            false
    end;
verify_password(_Password, _Encoded) ->
    false.

%% ── Internal helpers ────────────────────────────────────────────────────

%% Parse "$pbkdf2-sha256$i=<iter>$<salt_b64>$<hash_b64>" into its parts.
parse_phc(Encoded) ->
    case binary:split(Encoded, <<"$">>, [global]) of
        [<<>>, <<"pbkdf2-sha256">>, <<"i=", IterBin/binary>>, SaltB64, HashB64] ->
            try
                {ok, binary_to_integer(IterBin),
                     base64:decode(SaltB64),
                     base64:decode(HashB64)}
            catch _:_ ->
                error
            end;
        _ ->
            error
    end.

%% Constant-time comparison to prevent timing attacks (mirrors winn_jwt).
constant_time_compare(A, B) when byte_size(A) =/= byte_size(B) -> false;
constant_time_compare(A, B) ->
    constant_time_compare(A, B, 0).
constant_time_compare(<<>>, <<>>, Acc) -> Acc =:= 0;
constant_time_compare(<<X, RestA/binary>>, <<Y, RestB/binary>>, Acc) ->
    constant_time_compare(RestA, RestB, Acc bor (X bxor Y)).

normalize_algo(sha256) -> sha256;
normalize_algo(sha384) -> sha384;
normalize_algo(sha512) -> sha512;
normalize_algo(sha)    -> sha;
normalize_algo(md5)    -> md5.

bin_to_hex(Bin) ->
    list_to_binary([io_lib:format("~2.16.0b", [B]) || <<B>> <= Bin]).

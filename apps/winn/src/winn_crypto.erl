%% winn_crypto.erl
%% R5 — Crypto and hashing functions for Winn programs.
%%
%% Crypto.hash(:sha256, "data")
%% Crypto.hmac(:sha256, "secret", "data")
%% Crypto.random_bytes(32)
%% Crypto.base64_encode(bytes)
%% Crypto.base64_decode(string)

-module(winn_crypto).
-export([hash/2, hmac/3, random_bytes/1,
         base64_encode/1, base64_decode/1]).

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

%% ── Internal helpers ────────────────────────────────────────────────────

normalize_algo(sha256) -> sha256;
normalize_algo(sha384) -> sha384;
normalize_algo(sha512) -> sha512;
normalize_algo(sha)    -> sha;
normalize_algo(md5)    -> md5.

bin_to_hex(Bin) ->
    list_to_binary([io_lib:format("~2.16.0b", [B]) || <<B>> <= Bin]).

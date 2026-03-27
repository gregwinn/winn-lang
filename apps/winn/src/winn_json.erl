%% winn_json.erl
%% JSON encoding/decoding for Winn programs.
%%
%% JSON.encode(term)   -> binary
%% JSON.decode(binary) -> term

-module(winn_json).
-export([encode/1, decode/1]).

%% Encode an Erlang term to a JSON binary string.
%% Maps with atom keys have keys converted to strings.
encode(Term) ->
    jsone:encode(prepare(Term)).

%% Decode a JSON binary string to an Erlang term.
%% Object keys become atoms.
decode(Bin) when is_binary(Bin) ->
    jsone:decode(Bin, [{object_format, map}, {keys, atom}]).

%% ── Internal ────────────────────────────────────────────────────────────

prepare(M) when is_map(M) ->
    maps:fold(fun(K, V, Acc) ->
        BinK = if is_atom(K)   -> atom_to_binary(K, utf8);
                  is_binary(K) -> K;
                  true         -> list_to_binary(io_lib:format("~p", [K]))
               end,
        maps:put(BinK, prepare(V), Acc)
    end, #{}, M);
prepare(L) when is_list(L) ->
    [prepare(E) || E <- L];
prepare(nil) -> null;
prepare(A) when is_atom(A), A =/= true, A =/= false, A =/= null ->
    atom_to_binary(A, utf8);
prepare(Other) ->
    Other.

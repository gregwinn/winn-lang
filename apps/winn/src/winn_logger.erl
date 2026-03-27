%% winn_logger.erl
%% R4 — Structured JSON logging for Winn programs.
%%
%% Logger.info("message", %{key: val})
%% Logger.warn("message", %{key: val})
%% Logger.error("message", %{key: val})
%% Logger.debug("message", %{key: val})
%%
%% Output format: JSON line to stderr.
%% {"level":"info","msg":"message","key":"val","ts":"2026-03-27T12:00:00Z"}

-module(winn_logger).
-export([info/2, warn/2, error/2, debug/2,
         info/1, warn/1, error/1, debug/1]).

info(Msg)       -> log(<<"info">>,  Msg, #{}).
info(Msg, Meta) -> log(<<"info">>,  Msg, Meta).

warn(Msg)       -> log(<<"warn">>,  Msg, #{}).
warn(Msg, Meta) -> log(<<"warn">>,  Msg, Meta).

error(Msg)       -> log(<<"error">>, Msg, #{}).
error(Msg, Meta) -> log(<<"error">>, Msg, Meta).

debug(Msg)       -> log(<<"debug">>, Msg, #{}).
debug(Msg, Meta) -> log(<<"debug">>, Msg, Meta).

log(Level, Msg, Meta) when is_binary(Msg), is_map(Meta) ->
    Ts = format_ts(os:system_time(second)),
    Base = #{<<"level">> => Level, <<"msg">> => Msg, <<"ts">> => Ts},
    Merged = maps:merge(Base, encode_keys(Meta)),
    Line = json_encode(Merged),
    io:put_chars(standard_error, [Line, $\n]),
    ok.

%% Encode map keys from atoms to binaries for JSON output.
encode_keys(Map) ->
    maps:fold(fun(K, V, Acc) ->
        BinK = if is_atom(K) -> atom_to_binary(K, utf8);
                  is_binary(K) -> K;
                  true -> list_to_binary(io_lib:format("~p", [K]))
               end,
        maps:put(BinK, V, Acc)
    end, #{}, Map).

format_ts(Timestamp) ->
    GregorianSecs = Timestamp + 62167219200,
    {{Y,Mo,D},{H,Mi,S}} = calendar:gregorian_seconds_to_datetime(GregorianSecs),
    list_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
                                 [Y, Mo, D, H, Mi, S])).

%% Minimal JSON encoder — handles maps, binaries, atoms, integers, floats, lists.
json_encode(Map) when is_map(Map) ->
    Pairs = maps:fold(fun(K, V, Acc) ->
        [[$", escape_json(K), $", $:, json_encode(V)] | Acc]
    end, [], Map),
    [${, lists:join($,, Pairs), $}];
json_encode(Bin) when is_binary(Bin) ->
    [$", escape_json(Bin), $"];
json_encode(Atom) when is_atom(Atom) ->
    [$", atom_to_list(Atom), $"];
json_encode(Int) when is_integer(Int) ->
    integer_to_list(Int);
json_encode(Flt) when is_float(Flt) ->
    float_to_list(Flt, [{decimals, 10}, compact]);
json_encode(List) when is_list(List) ->
    [$[, lists:join($,, [json_encode(E) || E <- List]), $]].

escape_json(Bin) when is_binary(Bin) ->
    escape_json_chars(binary_to_list(Bin));
escape_json(List) when is_list(List) ->
    escape_json_chars(List).

escape_json_chars([]) -> [];
escape_json_chars([$" | T])  -> [$\\, $" | escape_json_chars(T)];
escape_json_chars([$\\ | T]) -> [$\\, $\\ | escape_json_chars(T)];
escape_json_chars([$\n | T]) -> [$\\, $n | escape_json_chars(T)];
escape_json_chars([$\r | T]) -> [$\\, $r | escape_json_chars(T)];
escape_json_chars([$\t | T]) -> [$\\, $t | escape_json_chars(T)];
escape_json_chars([C | T])   -> [C | escape_json_chars(T)].

%% winn_runtime.erl
%% Standard library functions callable from Winn programs.
%%
%% Naming convention: functions are named as 'module.function' atoms so
%% the codegen can map Winn's IO.puts → winn_runtime:'io.puts' etc.
%%
%% Phase 1: IO, basic string and type conversion.
%% Later phases will add Enum, Map, List, String, etc.

-module(winn_runtime).

-export([
    %% IO
    'io.puts'/1,
    'io.print'/1,
    'io.inspect'/1,

    %% String
    'string.upcase'/1,
    'string.downcase'/1,
    'string.trim'/1,
    'string.length'/1,
    'string.split'/2,
    'string.contains?'/2,
    'string.to_integer'/1,
    'string.to_float'/1,
    'string.replace'/3,
    'string.starts_with?'/2,
    'string.ends_with?'/2,
    'string.slice'/3,

    %% Enum
    'enum.map'/2,
    'enum.filter'/2,
    'enum.reduce'/3,
    'enum.each'/2,
    'enum.any?'/2,
    'enum.all?'/2,
    'enum.find'/2,
    'enum.count'/1,
    'enum.sort'/1,
    'enum.sort'/2,
    'enum.reverse'/1,
    'enum.join'/2,
    'enum.flat_map'/2,

    %% List
    'list.first'/1,
    'list.last'/1,
    'list.length'/1,
    'list.reverse'/1,
    'list.flatten'/1,
    'list.append'/2,
    'list.contains?'/2,

    %% Map
    'map.merge'/2,
    'map.get'/2,
    'map.put'/3,
    'map.keys'/1,
    'map.values'/1,
    'map.has_key?'/2,
    'map.delete'/2,

    %% Type conversions
    to_string/1,
    to_integer/1,
    to_float/1,
    to_atom/1,

    %% Introspection
    inspect/1,

    %% R1 — System (environment variables)
    'system.get_env'/1,
    'system.get_env'/2,
    'system.put_env'/2,

    %% R2 — UUID
    'uuid.v4'/0,

    %% R3 — DateTime
    'datetime.now'/0,
    'datetime.to_iso8601'/1,
    'datetime.from_iso8601'/1,
    'datetime.diff'/2,
    'datetime.format'/2
]).

%% ── IO ─────────────────────────────────────────────────────────────────────

'io.puts'(Str) when is_binary(Str) ->
    io:put_chars([Str, $\n]);
'io.puts'(Term) ->
    io:format("~p~n", [Term]).

'io.print'(Str) when is_binary(Str) ->
    io:put_chars(Str);
'io.print'(Term) ->
    io:format("~p", [Term]).

'io.inspect'(Term) ->
    io:format("~p~n", [Term]),
    Term.  %% Returns the value (like Elixir's IO.inspect)

%% ── String ─────────────────────────────────────────────────────────────────

'string.upcase'(Bin) when is_binary(Bin) ->
    string:uppercase(Bin).

'string.downcase'(Bin) when is_binary(Bin) ->
    string:lowercase(Bin).

'string.trim'(Bin) when is_binary(Bin) ->
    string:trim(Bin).

'string.length'(Bin) when is_binary(Bin) ->
    string:length(Bin).

'string.split'(Bin, Sep) when is_binary(Bin), is_binary(Sep) ->
    Parts = binary:split(Bin, Sep, [global]),
    Parts.

'string.contains?'(Bin, Sub) when is_binary(Bin), is_binary(Sub) ->
    binary:match(Bin, Sub) =/= nomatch.

'string.to_integer'(Bin) when is_binary(Bin) ->
    case string:to_integer(binary_to_list(Bin)) of
        {N, []}  -> {ok, N};
        _        -> {error, <<"invalid integer">>}
    end.

'string.to_float'(Bin) when is_binary(Bin) ->
    case string:to_float(binary_to_list(Bin)) of
        {F, []}  -> {ok, F};
        _        -> {error, <<"invalid float">>}
    end.

'string.replace'(Bin, Pattern, Replacement) when is_binary(Bin), is_binary(Pattern), is_binary(Replacement) ->
    binary:replace(Bin, Pattern, Replacement, [global]).

'string.starts_with?'(Bin, Prefix) when is_binary(Bin), is_binary(Prefix) ->
    PrefixSize = byte_size(Prefix),
    case Bin of
        <<Prefix:PrefixSize/binary, _/binary>> -> true;
        _ -> false
    end.

'string.ends_with?'(Bin, Suffix) when is_binary(Bin), is_binary(Suffix) ->
    BinSize = byte_size(Bin),
    SuffixSize = byte_size(Suffix),
    case BinSize >= SuffixSize of
        true ->
            Start = BinSize - SuffixSize,
            case Bin of
                <<_:Start/binary, Suffix:SuffixSize/binary>> -> true;
                _ -> false
            end;
        false ->
            false
    end.

'string.slice'(Bin, Start, Length) when is_binary(Bin), is_integer(Start), is_integer(Length) ->
    binary:part(Bin, Start, Length).

%% ── Enum ─────────────────────────────────────────────────────────────────

%% (List, Fun) order — used by block call desugaring: Enum.map(list) do |x| ... end
'enum.map'(List, Fun) when is_list(List), is_function(Fun) ->
    lists:map(Fun, List);
'enum.map'(Fun, List) when is_function(Fun), is_list(List) ->
    lists:map(Fun, List).

'enum.filter'(List, Fun) when is_list(List), is_function(Fun) ->
    lists:filter(Fun, List);
'enum.filter'(Fun, List) when is_function(Fun), is_list(List) ->
    lists:filter(Fun, List).

'enum.reduce'(List, Acc, Fun) when is_list(List), is_function(Fun) ->
    lists:foldl(Fun, Acc, List);
'enum.reduce'(Fun, Acc, List) when is_function(Fun), is_list(List) ->
    lists:foldl(Fun, Acc, List).

'enum.each'(List, Fun) when is_list(List), is_function(Fun) ->
    lists:foreach(Fun, List),
    ok;
'enum.each'(Fun, List) when is_function(Fun), is_list(List) ->
    lists:foreach(Fun, List),
    ok.

'enum.any?'(List, Fun) when is_list(List), is_function(Fun) ->
    lists:any(Fun, List);
'enum.any?'(Fun, List) when is_function(Fun), is_list(List) ->
    lists:any(Fun, List).

'enum.all?'(List, Fun) when is_list(List), is_function(Fun) ->
    lists:all(Fun, List);
'enum.all?'(Fun, List) when is_function(Fun), is_list(List) ->
    lists:all(Fun, List).

'enum.find'(List, Fun) when is_list(List), is_function(Fun) ->
    enum_find(Fun, List);
'enum.find'(Fun, List) when is_function(Fun), is_list(List) ->
    enum_find(Fun, List).

enum_find(_Fun, []) ->
    not_found;
enum_find(Fun, [H | T]) ->
    case Fun(H) of
        true -> {ok, H};
        false -> enum_find(Fun, T)
    end.

'enum.count'(List) when is_list(List) ->
    length(List).

'enum.sort'(List) when is_list(List) ->
    lists:sort(List).

'enum.sort'(List, Fun) when is_list(List), is_function(Fun) ->
    lists:sort(Fun, List);
'enum.sort'(Fun, List) when is_function(Fun), is_list(List) ->
    lists:sort(Fun, List).

'enum.reverse'(List) when is_list(List) ->
    lists:reverse(List).

'enum.join'(List, Sep) when is_list(List), is_binary(Sep) ->
    join_binaries(List, Sep).

join_binaries([], _Sep) ->
    <<>>;
join_binaries([H], _Sep) ->
    to_string(H);
join_binaries([H | T], Sep) ->
    lists:foldl(fun(Elem, Acc) ->
        <<Acc/binary, Sep/binary, (to_string(Elem))/binary>>
    end, to_string(H), T).

'enum.flat_map'(Fun, List) when is_function(Fun), is_list(List) ->
    lists:flatmap(Fun, List).

%% ── List ─────────────────────────────────────────────────────────────────

'list.first'([]) ->
    not_found;
'list.first'([H | _]) ->
    H.

'list.last'([]) ->
    not_found;
'list.last'(List) when is_list(List) ->
    lists:last(List).

'list.length'(List) when is_list(List) ->
    length(List).

'list.reverse'(List) when is_list(List) ->
    lists:reverse(List).

'list.flatten'(List) when is_list(List) ->
    lists:flatten(List).

'list.append'(List1, List2) when is_list(List1), is_list(List2) ->
    List1 ++ List2.

'list.contains?'(Elem, List) when is_list(List) ->
    lists:member(Elem, List).

%% ── Map ────────────────────────────────────────────────────────────────────

'map.merge'(Map1, Map2) -> maps:merge(Map1, Map2).
'map.get'(Key, Map)     -> maps:get(Key, Map).
'map.put'(Key, Val, Map) -> maps:put(Key, Val, Map).
'map.keys'(Map)          -> maps:keys(Map).
'map.values'(Map)        -> maps:values(Map).
'map.has_key?'(Key, Map) -> maps:is_key(Key, Map).
'map.delete'(Key, Map)   -> maps:remove(Key, Map).

%% ── Type conversions ───────────────────────────────────────────────────────

to_string(Bin) when is_binary(Bin)   -> Bin;
to_string(N)   when is_integer(N)    -> integer_to_binary(N);
to_string(F)   when is_float(F)      -> float_to_binary(F, [{decimals, 10}, compact]);
to_string(A)   when is_atom(A)       -> atom_to_binary(A, utf8);
to_string(L)   when is_list(L)       -> list_to_binary(L);
to_string(Term)                      -> list_to_binary(io_lib:format("~p", [Term])).

to_integer(N) when is_integer(N)    -> N;
to_integer(F) when is_float(F)      -> trunc(F);
to_integer(B) when is_binary(B)     -> binary_to_integer(B);
to_integer(L) when is_list(L)       -> list_to_integer(L).

to_float(F) when is_float(F)        -> F;
to_float(N) when is_integer(N)      -> float(N);
to_float(B) when is_binary(B)       -> binary_to_float(B);
to_float(L) when is_list(L)         -> list_to_float(L).

to_atom(A) when is_atom(A)          -> A;
to_atom(B) when is_binary(B)        -> binary_to_atom(B, utf8);
to_atom(L) when is_list(L)          -> list_to_atom(L).

%% ── Introspection ──────────────────────────────────────────────────────────

inspect(Term) ->
    list_to_binary(io_lib:format("~p", [Term])).

%% ── R1 — System (environment variables) ─────────────────────────────────

'system.get_env'(Key) when is_binary(Key) ->
    case os:getenv(binary_to_list(Key)) of
        false -> nil;
        Val   -> list_to_binary(Val)
    end.

'system.get_env'(Key, Default) when is_binary(Key), is_binary(Default) ->
    case os:getenv(binary_to_list(Key)) of
        false -> Default;
        Val   -> list_to_binary(Val)
    end.

'system.put_env'(Key, Val) when is_binary(Key), is_binary(Val) ->
    os:putenv(binary_to_list(Key), binary_to_list(Val)),
    ok.

%% ── R2 — UUID ───────────────────────────────────────────────────────────

'uuid.v4'() ->
    <<A:32, B:16, _:4, C:12, _:2, D:14, E:48>> = crypto:strong_rand_bytes(16),
    Bin = <<A:32, B:16, 4:4, C:12, 2#10:2, D:14, E:48>>,
    Hex = bin_to_hex(Bin),
    %% Hex is 32 chars; split into 8-4-4-4-12
    <<P1:8/binary, P2:4/binary, P3:4/binary, P4:4/binary, P5:12/binary>> = Hex,
    <<P1/binary, $-, P2/binary, $-, P3/binary, $-, P4/binary, $-, P5/binary>>.

bin_to_hex(Bin) ->
    list_to_binary([io_lib:format("~2.16.0b", [B]) || <<B>> <= Bin]).

%% ── R3 — DateTime ──────────────────────────────────────────────────────

'datetime.now'() ->
    os:system_time(second).

'datetime.to_iso8601'(Timestamp) when is_integer(Timestamp) ->
    GregorianSecs = Timestamp + 62167219200,  %% epoch offset
    {{Y,Mo,D},{H,Mi,S}} = calendar:gregorian_seconds_to_datetime(GregorianSecs),
    list_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
                                 [Y, Mo, D, H, Mi, S])).

'datetime.from_iso8601'(Bin) when is_binary(Bin) ->
    Str = binary_to_list(Bin),
    case io_lib:fread("~4d-~2d-~2dT~2d:~2d:~2d", Str) of
        {ok, [Y,Mo,D,H,Mi,S], _} ->
            GregorianSecs = calendar:datetime_to_gregorian_seconds({{Y,Mo,D},{H,Mi,S}}),
            {ok, GregorianSecs - 62167219200};
        _ ->
            {error, <<"invalid ISO 8601 format">>}
    end.

'datetime.diff'(T1, T2) when is_integer(T1), is_integer(T2) ->
    T1 - T2.

'datetime.format'(Timestamp, FormatBin) when is_integer(Timestamp), is_binary(FormatBin) ->
    GregorianSecs = Timestamp + 62167219200,
    {{Y,Mo,D},{H,Mi,S}} = calendar:gregorian_seconds_to_datetime(GregorianSecs),
    Format = binary_to_list(FormatBin),
    Result = lists:flatten(format_dt(Format, Y, Mo, D, H, Mi, S)),
    list_to_binary(Result).

format_dt([], _Y, _Mo, _D, _H, _Mi, _S) -> [];
format_dt([$%, $Y | Rest], Y, Mo, D, H, Mi, S) ->
    [io_lib:format("~4..0B", [Y]) | format_dt(Rest, Y, Mo, D, H, Mi, S)];
format_dt([$%, $m | Rest], Y, Mo, D, H, Mi, S) ->
    [io_lib:format("~2..0B", [Mo]) | format_dt(Rest, Y, Mo, D, H, Mi, S)];
format_dt([$%, $d | Rest], Y, Mo, D, H, Mi, S) ->
    [io_lib:format("~2..0B", [D]) | format_dt(Rest, Y, Mo, D, H, Mi, S)];
format_dt([$%, $H | Rest], Y, Mo, D, H, Mi, S) ->
    [io_lib:format("~2..0B", [H]) | format_dt(Rest, Y, Mo, D, H, Mi, S)];
format_dt([$%, $M | Rest], Y, Mo, D, H, Mi, S) ->
    [io_lib:format("~2..0B", [Mi]) | format_dt(Rest, Y, Mo, D, H, Mi, S)];
format_dt([$%, $S | Rest], Y, Mo, D, H, Mi, S) ->
    [io_lib:format("~2..0B", [S]) | format_dt(Rest, Y, Mo, D, H, Mi, S)];
format_dt([C | Rest], Y, Mo, D, H, Mi, S) ->
    [C | format_dt(Rest, Y, Mo, D, H, Mi, S)].

%% winn_protocol.erl
%% Protocol dispatch runtime: ETS-backed registration and dispatch.

-module(winn_protocol).
-export([init/0, register_impl/4, dispatch/3]).

-define(TABLE, winn_protocol_table).

%% ── Initialization ──────────────────────────────────────────────────────────

init() ->
    case ets:whereis(?TABLE) of
        undefined ->
            ets:new(?TABLE, [named_table, public, set, {read_concurrency, true}]),
            ok;
        _ ->
            ok
    end.

%% ── Registration ────────────────────────────────────────────────────────────
%% Called at module load time to register a protocol implementation.
%% register_impl(printable, to_s, user, {user_mod, '__impl_printable_to_s'})

register_impl(Protocol, Method, StructType, {Mod, Fun}) ->
    ensure_init(),
    ets:insert(?TABLE, {{Protocol, Method, StructType}, Mod, Fun}),
    ok.

%% ── Dispatch ────────────────────────────────────────────────────────────────
%% dispatch(printable, to_s, [UserStruct])
%% Reads __struct__ from first arg, looks up implementation, calls it.

dispatch(Protocol, Method, Args) ->
    ensure_init(),
    [First | _] = Args,
    StructType = case First of
        Map when is_map(Map) ->
            case maps:get('__struct__', Map, undefined) of
                undefined -> error({protocol_not_implemented, Protocol, Method, no_struct});
                Type -> Type
            end;
        Atom when is_atom(Atom) -> Atom;
        _ -> error({protocol_not_implemented, Protocol, Method, First})
    end,
    case ets:lookup(?TABLE, {Protocol, Method, StructType}) of
        [{_, Mod, Fun}] ->
            erlang:apply(Mod, Fun, Args);
        [] ->
            error({protocol_not_implemented, Protocol, Method, StructType})
    end.

%% ── Internal ────────────────────────────────────────────────────────────────

ensure_init() ->
    case ets:whereis(?TABLE) of
        undefined -> init();
        _ -> ok
    end.

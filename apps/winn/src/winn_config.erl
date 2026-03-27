%% winn_config.erl
%% M2 — Configuration system for Winn programs.
%%
%% Config.get(:section, :key)          -> value | nil
%% Config.get(:section, :key, default) -> value | default
%% Config.put(:section, :key, value)   -> ok
%% Config.load(config_map)             -> ok
%%
%% Backed by ETS for fast concurrent reads.

-module(winn_config).
-export([get/2, get/3, put/3, load/1, init/0]).

-define(TABLE, winn_config_table).

%% Initialize the ETS table. Idempotent.
init() ->
    case ets:whereis(?TABLE) of
        undefined ->
            ets:new(?TABLE, [named_table, public, set, {read_concurrency, true}]),
            ok;
        _ ->
            ok
    end.

%% Get a config value. Returns nil if not found.
get(Section, Key) when is_atom(Section), is_atom(Key) ->
    ensure_init(),
    case ets:lookup(?TABLE, {Section, Key}) of
        [{_, Val}] -> Val;
        []         -> nil
    end.

%% Get with default.
get(Section, Key, Default) when is_atom(Section), is_atom(Key) ->
    case get(Section, Key) of
        nil -> Default;
        Val -> Val
    end.

%% Put a config value.
put(Section, Key, Value) when is_atom(Section), is_atom(Key) ->
    ensure_init(),
    ets:insert(?TABLE, {{Section, Key}, Value}),
    ok.

%% Load a map of %{section => %{key => value}} into config.
load(ConfigMap) when is_map(ConfigMap) ->
    ensure_init(),
    maps:fold(fun(Section, SectionMap, _) ->
        maps:fold(fun(Key, Val, _) ->
            put(Section, Key, Val)
        end, ok, SectionMap)
    end, ok, ConfigMap),
    ok.

%% ── Internal ────────────────────────────────────────────────────────────

ensure_init() ->
    case ets:whereis(?TABLE) of
        undefined -> init();
        _         -> ok
    end.

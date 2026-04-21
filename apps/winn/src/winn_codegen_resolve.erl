%% winn_codegen_resolve.erl
%% Module name resolution and atom helpers for codegen.
%%
%% Maps Winn module names (IO, String, Enum, etc.) to their Erlang
%% module + function targets. Extracted from winn_codegen.erl for
%% maintainability — each new stdlib module adds a clause here.

-module(winn_codegen_resolve).
-export([resolve_dot_call/2, resolve_atom/1, winn_module_atom/1, fn_atom/1, var_atom/1]).

%% ── Module/function name resolution ───────────────────────────────────────
%%
%% Maps Winn's PascalCase module calls to Erlang module + function pairs.
%% To add a new Winn module: add a clause here and create winn_newmod.erl.

resolve_dot_call('IO', Fun) ->
    {winn_runtime, list_to_atom("io." ++ atom_to_list(Fun))};
resolve_dot_call('String', Fun) ->
    {winn_runtime, list_to_atom("string." ++ atom_to_list(Fun))};
resolve_dot_call('Enum', Fun) ->
    {winn_runtime, list_to_atom("enum." ++ atom_to_list(Fun))};
resolve_dot_call('Map', Fun) ->
    {winn_runtime, list_to_atom("map." ++ atom_to_list(Fun))};
resolve_dot_call('List', Fun) ->
    {winn_runtime, list_to_atom("list." ++ atom_to_list(Fun))};
resolve_dot_call('GenServer', Fun) -> {gen_server, Fun};
resolve_dot_call('Supervisor', Fun) -> {supervisor, Fun};
resolve_dot_call('Repo', Fun)       -> {winn_repo, Fun};
resolve_dot_call('Changeset', Fun)  -> {winn_changeset, Fun};
resolve_dot_call('System', Fun) ->
    {winn_runtime, list_to_atom("system." ++ atom_to_list(Fun))};
resolve_dot_call('UUID', Fun) ->
    {winn_runtime, list_to_atom("uuid." ++ atom_to_list(Fun))};
resolve_dot_call('DateTime', Fun) ->
    {winn_runtime, list_to_atom("datetime." ++ atom_to_list(Fun))};
resolve_dot_call('Logger', Fun)  -> {winn_logger, Fun};
resolve_dot_call('Crypto', Fun)  -> {winn_crypto, Fun};
resolve_dot_call('HTTP', Fun)    -> {winn_http, Fun};
resolve_dot_call('Config', Fun)  -> {winn_config, Fun};
resolve_dot_call('Task', Fun)    -> {winn_task, Fun};
resolve_dot_call('JWT', Fun)     -> {winn_jwt, Fun};
resolve_dot_call('WS', Fun)      -> {winn_ws, Fun};
resolve_dot_call('Server', Fun)  -> {winn_server, Fun};
resolve_dot_call('JSON', Fun)    -> {winn_json, Fun};
resolve_dot_call('Winn', Fun)    -> {winn_runtime, Fun};
resolve_dot_call('Retry', Fun)    -> {winn_retry, Fun};
resolve_dot_call('Timer', Fun)    -> {winn_timer, Fun};
resolve_dot_call('File', Fun)     -> {winn_file, Fun};
resolve_dot_call('Regex', Fun) -> {winn_regex, Fun};
resolve_dot_call('Protocol', Fun) -> {winn_protocol, Fun};
resolve_dot_call('Health', Fun)   -> {winn_health, Fun};
resolve_dot_call('Metrics', Fun)  -> {winn_metrics, Fun};
resolve_dot_call('Agent', Fun)    -> {winn_agent, Fun};
resolve_dot_call('Pipeline', Fun) -> {winn_pipeline, Fun};
resolve_dot_call('ReplBindings', get) -> {winn_repl, get_binding};
resolve_dot_call(Mod, Fun) ->
    ErlMod = list_to_atom(string:lowercase(atom_to_list(Mod))),
    {ErlMod, Fun}.

%% ── Name helpers ───────────────────────────────────────────────────────────

%% Convert a Winn module name to its compiled atom: HelloWorld -> helloworld
winn_module_atom(Name) when is_atom(Name) ->
    list_to_atom(string:lowercase(atom_to_list(Name))).

%% Function name atom (identity — reserved for future mangling).
fn_atom(Name) when is_atom(Name) -> Name.

%% Module name references (PascalCase) used as values are lowercased
%% to match compiled module names: Post -> post.
%% Regular atoms (:ok, :error, etc.) are left as-is.
resolve_atom(V) when is_atom(V) ->
    Str = atom_to_list(V),
    case Str of
        [C | _] when C >= $A, C =< $Z ->
            list_to_atom(string:lowercase(Str));
        _ ->
            V
    end.

%% Capitalise the first letter of a variable name for Core Erlang convention.
%% Only lowercase ASCII letters are capitalised; _ and uppercase are left alone.
var_atom(Name) when is_atom(Name) ->
    case atom_to_list(Name) of
        [C | Rest] when C >= $a, C =< $z ->
            list_to_atom([(C - 32) | Rest]);
        Chars ->
            list_to_atom(Chars)
    end.

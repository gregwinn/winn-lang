%% winn_repo_sqlite.erl
%% SQLite adapter for winn_repo.
%% Uses esqlite NIF for database operations.

-module(winn_repo_sqlite).
-export([connect/1, query/3, execute/2, execute/3, close/1,
         translate_sql/1, translate_params/1]).

%% ── Connection ───────────────────────────────────────────────────────────────

connect(Config) ->
    DbPath = maps:get(database, Config, "winn_dev.db"),
    Path = case is_binary(DbPath) of
        true  -> binary_to_list(DbPath);
        false -> DbPath
    end,
    esqlite3:open(Path).

close(Conn) ->
    esqlite3:close(Conn).

%% ── Query (returns rows) ────────────────────────────────────────────────────

query(Conn, SQL, Params) ->
    SqlStr = translate_sql(SQL),
    TransParams = translate_params(Params),
    case esqlite3:q(Conn, SqlStr, TransParams) of
        Rows when is_list(Rows) ->
            {ok, Rows};
        {error, Reason} ->
            {error, Reason}
    end.

%% ── Execute (returns affected count or ok) ──────────────────────────────────

execute(Conn, SQL) ->
    execute(Conn, SQL, []).

execute(Conn, SQL, Params) ->
    SqlStr = translate_sql(SQL),
    TransParams = translate_params(Params),
    case esqlite3:exec(Conn, SqlStr, TransParams) of
        ok              -> {ok, 0};
        {ok, Count}     -> {ok, Count};
        {error, Reason} -> {error, Reason};
        _               -> ok
    end.

%% ── SQL translation ─────────────────────────────────────────────────────────
%% PostgreSQL uses $1, $2, ... for parameters
%% SQLite uses ?, ?, ... for parameters

translate_sql(SQL) when is_binary(SQL) ->
    translate_sql(binary_to_list(SQL));
translate_sql(SQL) when is_list(SQL) ->
    re:replace(SQL, "\\$[0-9]+", "?", [global, {return, list}]).

%% Translate parameter values for SQLite compatibility
translate_params(Params) ->
    [translate_value(V) || V <- Params].

translate_value(V) when is_binary(V)  -> V;
translate_value(V) when is_integer(V) -> V;
translate_value(V) when is_float(V)   -> V;
translate_value(true)                 -> 1;
translate_value(false)                -> 0;
translate_value(null)                 -> nil;
translate_value(nil)                  -> nil;
translate_value(V) when is_atom(V)    -> atom_to_binary(V, utf8);
translate_value(V) when is_list(V)    -> list_to_binary(V);
translate_value(V)                    -> V.

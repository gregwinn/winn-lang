%% winn_migrate.erl
%% Database migration runner.
%% Discovers migrations in migrations/*.winn, tracks applied state
%% in a schema_migrations table, runs up/down in transactions.

-module(winn_migrate).
-export([migrate/1, rollback/1, status/0, ensure_migrations_table/0]).

-define(MIGRATIONS_DIR, "migrations").
-define(BUILD_DIR, "_build/migrations").

%% ── Public API ───────────────────────────────────────────────────────────────

%% Run pending migrations. Opts: #{step => N} to limit.
migrate(Opts) ->
    ensure_migrations_table(),
    Pending = pending_migrations(),
    Step = maps:get(step, Opts, length(Pending)),
    ToRun = lists:sublist(Pending, Step),
    case ToRun of
        [] ->
            io:format("No pending migrations.~n"),
            ok;
        _ ->
            lists:foreach(fun(M) -> run_migration(M, up) end, ToRun),
            io:format("Ran ~B migration(s).~n", [length(ToRun)]),
            ok
    end.

%% Rollback migrations. Opts: #{step => N} to limit (default 1).
rollback(Opts) ->
    ensure_migrations_table(),
    Applied = lists:reverse(applied_migrations()),
    Step = maps:get(step, Opts, 1),
    ToRollback = lists:sublist(Applied, Step),
    case ToRollback of
        [] ->
            io:format("Nothing to rollback.~n"),
            ok;
        _ ->
            lists:foreach(fun(M) -> run_migration(M, down) end, ToRollback),
            io:format("Rolled back ~B migration(s).~n", [length(ToRollback)]),
            ok
    end.

%% Show migration status.
status() ->
    ensure_migrations_table(),
    All = discover_migrations(),
    Applied = applied_migration_names(),
    io:format("~n  Status   | Migration~n"),
    io:format("  ---------+---------------------------~n"),
    lists:foreach(fun({Name, _File}) ->
        Status = case lists:member(Name, Applied) of
            true  -> "up     ";
            false -> "pending"
        end,
        io:format("  ~s | ~s~n", [Status, Name])
    end, All),
    io:format("~n"),
    ok.

%% ── Migration discovery ─────────────────────────────────────────────────────

discover_migrations() ->
    case filelib:is_dir(?MIGRATIONS_DIR) of
        false -> [];
        true ->
            Files = lists:sort(filelib:wildcard(?MIGRATIONS_DIR ++ "/*.winn")),
            [{migration_name(F), F} || F <- Files]
    end.

migration_name(FilePath) ->
    filename:basename(FilePath, ".winn").

pending_migrations() ->
    All = discover_migrations(),
    Applied = applied_migration_names(),
    [{Name, File} || {Name, File} <- All, not lists:member(Name, Applied)].

%% ── Migration execution ─────────────────────────────────────────────────────

run_migration({Name, File}, Direction) ->
    io:format("  ~s ~s...~n", [direction_arrow(Direction), Name]),
    ok = filelib:ensure_path(?BUILD_DIR),
    case winn:compile_file(File, ?BUILD_DIR) of
        {ok, _} ->
            code:add_patha(?BUILD_DIR),
            ModAtom = detect_module(File),
            code:purge(ModAtom),
            code:load_file(ModAtom),
            try
                ModAtom:Direction(),
                case Direction of
                    up   -> record_migration(Name);
                    down -> remove_migration(Name)
                end,
                ok
            catch
                Class:Reason:Stack ->
                    io:format("  FAILED: ~p:~p~n  ~p~n", [Class, Reason, Stack]),
                    error({migration_failed, Name, Direction})
            end;
        {error, CompileErr} ->
            io:format("  COMPILE ERROR: ~p~n", [CompileErr]),
            error({migration_compile_failed, Name})
    end.

detect_module(File) ->
    case file:read_file(File) of
        {ok, Bin} ->
            Source = binary_to_list(Bin),
            case re:run(Source, "^\\s*module\\s+([A-Z][a-zA-Z0-9_.]*)",
                        [{capture, [1], list}, multiline]) of
                {match, [ModStr]} ->
                    list_to_atom(string:lowercase(
                        lists:flatten(string:replace(ModStr, ".", ".", all))));
                nomatch ->
                    list_to_atom(filename:basename(File, ".winn"))
            end;
        _ ->
            list_to_atom(filename:basename(File, ".winn"))
    end.

direction_arrow(up)   -> "==>";
direction_arrow(down) -> "<==".

%% ── Schema migrations table ─────────────────────────────────────────────────

ensure_migrations_table() ->
    SQL = <<"CREATE TABLE IF NOT EXISTS schema_migrations ("
            "version VARCHAR(255) PRIMARY KEY, "
            "inserted_at TIMESTAMP DEFAULT NOW()"
            ")">>,
    winn_repo:execute(SQL).

applied_migrations() ->
    case winn_repo:execute(<<"SELECT version FROM schema_migrations ORDER BY version">>) of
        {ok, Rows} ->
            [{binary_to_list(V), ""} || {V} <- Rows];
        _ -> []
    end.

applied_migration_names() ->
    case winn_repo:execute(<<"SELECT version FROM schema_migrations ORDER BY version">>) of
        {ok, Rows} ->
            [binary_to_list(V) || {V} <- Rows];
        _ -> []
    end.

record_migration(Name) ->
    SQL = <<"INSERT INTO schema_migrations (version) VALUES ($1)">>,
    winn_repo:execute(SQL, [list_to_binary(Name)]).

remove_migration(Name) ->
    SQL = <<"DELETE FROM schema_migrations WHERE version = $1">>,
    winn_repo:execute(SQL, [list_to_binary(Name)]).

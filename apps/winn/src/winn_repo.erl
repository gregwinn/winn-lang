-module(winn_repo).
-export([
    configure/1, insert/2, get/2, get/3, all/1, all/2,
    delete/1, update/1, execute/1, execute/2,
    'query.new'/1, 'query.where'/3, 'query.limit'/2,
    sql_for_insert/2, sql_for_select/2
]).

%% Configure the database connection from Winn:
%%   Repo.configure(%{host: "localhost", database: "my_app", ...})
configure(Config) when is_map(Config) ->
    winn_config:ensure_init(),
    maps:fold(fun(Key, Val, _) ->
        winn_config:put(repo, Key, Val)
    end, ok, Config),
    ok.

db_config() ->
    %% Read from Config ETS first, fall back to application env, then defaults.
    Defaults = #{
        host => "localhost", port => 5432,
        database => "winn_dev", username => "postgres", password => ""
    },
    AppConfig = case application:get_env(winn, repo_config) of
        {ok, C} -> C;
        undefined -> #{}
    end,
    EtsConfig = read_ets_config(),
    maps:merge(maps:merge(Defaults, AppConfig), EtsConfig).

read_ets_config() ->
    Keys = [host, port, database, username, password],
    lists:foldl(fun(Key, Acc) ->
        case winn_config:get(repo, Key) of
            nil -> Acc;
            Val -> maps:put(Key, Val, Acc)
        end
    end, #{}, Keys).

connect() ->
    #{host := Host, port := Port, database := DB,
      username := User, password := Pass} = db_config(),
    epgsql:connect(#{host => Host, port => Port, database => DB,
                     username => User, password => Pass}).

%% Query builder
'query.new'(SchemaMod) ->
    #{schema => SchemaMod, wheres => [], limit => all}.

'query.where'(Query, Field, Value) ->
    Wheres = maps:get(wheres, Query),
    Query#{wheres => [{Field, Value} | Wheres]}.

'query.limit'(Query, N) ->
    Query#{limit => N}.

%% SQL generation helpers (usable in tests without a DB)
sql_for_insert(SchemaMod, Attrs) ->
    Table  = SchemaMod:'__schema__'(source),
    Fields = SchemaMod:'__schema__'(fields),
    KVs    = [{F, maps:get(F, Attrs, null)} || F <- Fields],
    Cols   = [atom_to_binary(F, utf8) || {F, _} <- KVs],
    Params = [<<"$", (integer_to_binary(I))/binary>> || I <- lists:seq(1, length(KVs))],
    Vals   = [V || {_, V} <- KVs],
    SQL    = iolist_to_binary([
        "INSERT INTO ", Table,
        " (", lists:join(<<", ">>, Cols), ")",
        " VALUES (", lists:join(<<", ">>, Params), ")",
        " RETURNING *"
    ]),
    {SQL, Vals}.

sql_for_select(SchemaMod, Wheres) ->
    Table = SchemaMod:'__schema__'(source),
    case maps:to_list(Wheres) of
        [] ->
            {iolist_to_binary(["SELECT * FROM ", Table]), []};
        KVs ->
            Clauses = [iolist_to_binary([atom_to_binary(F, utf8), " = $", integer_to_binary(I)])
                       || {I, {F, _}} <- lists:zip(lists:seq(1, length(KVs)), KVs)],
            Vals = [V || {_, V} <- KVs],
            SQL  = iolist_to_binary(["SELECT * FROM ", Table,
                                     " WHERE ", lists:join(<<" AND ">>, Clauses)]),
            {SQL, Vals}
    end.

%% CRUD — require epgsql connection
insert(SchemaMod, Attrs) ->
    {SQL, Vals} = sql_for_insert(SchemaMod, Attrs),
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), Vals) of
            {ok, _Cols, [Row | _]} -> {ok, row_to_map(SchemaMod, Row)};
            {ok, _Cols, []}        -> {error, not_found};
            {error, Reason}        -> {error, Reason}
        end
    end).

get(SchemaMod, Id) ->
    Table = SchemaMod:'__schema__'(source),
    SQL   = iolist_to_binary(["SELECT * FROM ", Table, " WHERE id = $1 LIMIT 1"]),
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), [Id]) of
            {ok, _Cols, [Row | _]} -> {ok, row_to_map(SchemaMod, Row)};
            {ok, _Cols, []}        -> {error, not_found};
            {error, Reason}        -> {error, Reason}
        end
    end).

get(SchemaMod, Field, Value) ->
    Table = SchemaMod:'__schema__'(source),
    Col   = atom_to_binary(Field, utf8),
    SQL   = iolist_to_binary(["SELECT * FROM ", Table, " WHERE ", Col, " = $1 LIMIT 1"]),
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), [Value]) of
            {ok, _Cols, [Row | _]} -> {ok, row_to_map(SchemaMod, Row)};
            {ok, _Cols, []}        -> {error, not_found};
            {error, Reason}        -> {error, Reason}
        end
    end).

all(SchemaMod) ->
    Table = SchemaMod:'__schema__'(source),
    SQL   = iolist_to_binary(["SELECT * FROM ", Table]),
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), []) of
            {ok, Cols, Rows} -> {ok, [row_to_map_cols(Cols, R) || R <- Rows]};
            {error, Reason}  -> {error, Reason}
        end
    end).

all(SchemaMod, Wheres) ->
    {SQL, Vals} = sql_for_select(SchemaMod, Wheres),
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), Vals) of
            {ok, Cols, Rows} -> {ok, [row_to_map_cols(Cols, R) || R <- Rows]};
            {error, Reason}  -> {error, Reason}
        end
    end).

delete(#{id := Id} = Struct) ->
    case maps:get('__schema__', Struct, undefined) of
        undefined -> {error, not_a_schema_struct};
        SchemaMod ->
            Table = SchemaMod:'__schema__'(source),
            SQL   = iolist_to_binary(["DELETE FROM ", Table, " WHERE id = $1"]),
            with_conn(fun(Conn) ->
                case epgsql:equery(Conn, binary_to_list(SQL), [Id]) of
                    {ok, _} -> ok;
                    {error, R} -> {error, R}
                end
            end)
    end.

update(#{id := Id} = Struct) ->
    case maps:get('__schema__', Struct, undefined) of
        undefined -> {error, not_a_schema_struct};
        SchemaMod ->
            Table  = SchemaMod:'__schema__'(source),
            Fields = SchemaMod:'__schema__'(fields),
            KVs    = [{F, maps:get(F, Struct, null)} || F <- Fields],
            Sets   = [iolist_to_binary([atom_to_binary(F, utf8), " = $", integer_to_binary(I)])
                      || {I, {F, _}} <- lists:zip(lists:seq(1, length(KVs)), KVs)],
            Vals   = [V || {_, V} <- KVs] ++ [Id],
            SQL    = iolist_to_binary(["UPDATE ", Table, " SET ", lists:join(<<", ">>, Sets),
                                       " WHERE id = $", integer_to_binary(length(KVs) + 1),
                                       " RETURNING *"]),
            with_conn(fun(Conn) ->
                case epgsql:equery(Conn, binary_to_list(SQL), Vals) of
                    {ok, _Cols, [Row | _]} -> {ok, row_to_map(SchemaMod, Row)};
                    {ok, _Cols, []}        -> {error, not_found};
                    {error, Reason}        -> {error, Reason}
                end
            end)
    end.

%% Raw SQL execution
execute(SQL) when is_binary(SQL) ->
    execute(SQL, []).

execute(SQL, Params) when is_binary(SQL), is_list(Params) ->
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), Params) of
            {ok, _Cols, Rows}  -> {ok, Rows};
            {ok, Count}        -> {ok, Count};
            {error, Reason}    -> {error, Reason}
        end
    end).

with_conn(Fun) ->
    case connect() of
        {ok, Conn} ->
            Result = Fun(Conn),
            epgsql:close(Conn),
            Result;
        {error, Reason} ->
            {error, {connection_failed, Reason}}
    end.

row_to_map(SchemaMod, Row) ->
    Fields = SchemaMod:'__schema__'(fields),
    Values = tuple_to_list(Row),
    maps:from_list(lists:zip(Fields, lists:sublist(Values, length(Fields)))).

row_to_map_cols(Cols, Row) ->
    ColNames = [binary_to_atom(element(2, C), utf8) || C <- Cols],
    Values   = tuple_to_list(Row),
    maps:from_list(lists:zip(ColNames, Values)).

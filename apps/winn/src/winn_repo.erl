-module(winn_repo).
-export([
    configure/1, start_pool/0, pool_status/0,
    insert/2, get/2, get/3, all/1, all/2,
    delete/1, update/1, execute/1, execute/2,
    transaction/1, count/1, aggregate/3,
    'query.new'/1, 'query.where'/3, 'query.limit'/2,
    'query.order_by'/3, 'query.select'/2, 'query.count'/1,
    sql_for_insert/2, sql_for_select/2,
    build_where/1, normalize_epgsql_config/1
]).

%% Configure the database connection from Winn:
%%   Repo.configure(%{host: "localhost", database: "my_app", ...})
configure(Config) when is_map(Config) ->
    winn_config:ensure_init(),
    maps:fold(fun(Key, Val, _) ->
        winn_config:put(repo, Key, Val)
    end, ok, Config),
    %% Auto-start the connection pool if pool_size is configured
    case maps:get(pool_size, Config, undefined) of
        undefined -> ok;
        _ -> start_pool()
    end,
    ok.

%% Start the connection pool with current config.
start_pool() ->
    Config = db_config(),
    PoolSize = maps:get(pool_size, Config, 5),
    FullConfig = Config#{pool_size => PoolSize},
    case whereis(winn_pool) of
        undefined -> winn_pool:start(FullConfig);
        _Pid      -> ok  %% already running
    end.

%% Get pool status (idle/busy/max connections).
pool_status() ->
    case whereis(winn_pool) of
        undefined -> {error, pool_not_started};
        _Pid      -> {ok, winn_pool:status()}
    end.

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
    Keys = [host, port, database, username, password, pool_size, adapter],
    lists:foldl(fun(Key, Acc) ->
        case winn_config:get(repo, Key) of
            nil -> Acc;
            Val -> maps:put(Key, Val, Acc)
        end
    end, #{}, Keys).

connect() ->
    Config = db_config(),
    case maps:get(adapter, Config, postgres) of
        sqlite ->
            winn_repo_sqlite:connect(Config);
        _ ->
            epgsql:connect(normalize_epgsql_config(Config))
    end.

%% Normalize a db config map into the shape epgsql expects.
%% Winn code calls `Repo.configure(%{host: "...", ...})` which stores
%% the values as binaries in ETS. epgsql forwards `host` to
%% `gen_tcp:connect/4` which rejects binaries, so we must convert
%% string-like fields to charlists before calling epgsql:connect/1.
%%
%% Normalizes in place so callers can pass additional epgsql options
%% (ssl, ssl_opts, timeout, connect_timeout, ...) without losing them.
normalize_epgsql_config(Config) when is_map(Config) ->
    StringKeys = [host, database, username, password],
    lists:foldl(fun(Key, Acc) ->
        case maps:find(Key, Acc) of
            {ok, V} -> Acc#{Key => to_charlist(V)};
            error   -> Acc
        end
    end, Config, StringKeys).

to_charlist(V) when is_binary(V) -> binary_to_list(V);
to_charlist(V) when is_list(V)   -> V;
to_charlist(V) when is_atom(V)   -> atom_to_list(V).

adapter() ->
    maps:get(adapter, db_config(), postgres).

%% Query builder
'query.new'(SchemaMod) ->
    #{schema => SchemaMod, wheres => [], limit => all,
      order_by => none, select => all}.

'query.where'(Query, Field, Value) ->
    Wheres = maps:get(wheres, Query),
    Query#{wheres => [{Field, Value} | Wheres]}.

'query.limit'(Query, N) ->
    Query#{limit => N}.

'query.order_by'(Query, Field, Direction) ->
    Query#{order_by => {Field, Direction}}.

'query.select'(Query, Fields) when is_list(Fields) ->
    Query#{select => Fields}.

'query.count'(Query) ->
    #{schema := SchemaMod, wheres := Wheres} = Query,
    Table = SchemaMod:'__schema__'(source),
    {WhereSQL, Vals} = build_where(Wheres),
    SQL = iolist_to_binary(["SELECT COUNT(*) FROM ", Table, WhereSQL]),
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), Vals) of
            {ok, _Cols, [{Count}]} -> {ok, Count};
            {error, Reason}        -> {error, Reason}
        end
    end).

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

all(SchemaMod, Wheres) when is_map(Wheres), is_map_key(schema, Wheres) ->
    %% Query map from query builder
    #{schema := _Mod, wheres := WherePairs} = Wheres,
    OrderBy = maps:get(order_by, Wheres, none),
    Limit = maps:get(limit, Wheres, all),
    SelectFields = maps:get(select, Wheres, all),
    Table = SchemaMod:'__schema__'(source),
    {WhereSQL, Vals} = build_where(WherePairs),
    SelectStr = case SelectFields of
        all -> <<"*">>;
        Fields -> iolist_to_binary(lists:join(<<", ">>,
                    [atom_to_binary(F, utf8) || F <- Fields]))
    end,
    OrderSQL = case OrderBy of
        none -> <<>>;
        {Field, Dir} ->
            DirStr = case Dir of asc -> <<"ASC">>; desc -> <<"DESC">>; _ -> <<"ASC">> end,
            iolist_to_binary([" ORDER BY ", atom_to_binary(Field, utf8), " ", DirStr])
    end,
    LimitSQL = case Limit of
        all -> <<>>;
        N when is_integer(N) -> iolist_to_binary([" LIMIT ", integer_to_binary(N)])
    end,
    SQL = iolist_to_binary(["SELECT ", SelectStr, " FROM ", Table, WhereSQL, OrderSQL, LimitSQL]),
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), Vals) of
            {ok, Cols, Rows} -> {ok, [row_to_map_cols(Cols, R) || R <- Rows]};
            {error, Reason}  -> {error, Reason}
        end
    end);
all(SchemaMod, Wheres) ->
    {SQL, Vals} = sql_for_select(SchemaMod, Wheres),
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), Vals) of
            {ok, Cols, Rows} -> {ok, [row_to_map_cols(Cols, R) || R <- Rows]};
            {error, Reason}  -> {error, Reason}
        end
    end).

count(SchemaMod) ->
    Table = SchemaMod:'__schema__'(source),
    SQL   = iolist_to_binary(["SELECT COUNT(*) FROM ", Table]),
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), []) of
            {ok, _Cols, [{Count}]} -> {ok, Count};
            {error, Reason}        -> {error, Reason}
        end
    end).

%% Aggregate: sum, avg, min, max
aggregate(SchemaMod, Func, Field) when
        Func =:= sum; Func =:= avg; Func =:= min; Func =:= max ->
    Table = SchemaMod:'__schema__'(source),
    FuncStr = string:uppercase(atom_to_list(Func)),
    ColStr  = atom_to_binary(Field, utf8),
    SQL = iolist_to_binary(["SELECT ", FuncStr, "(", ColStr, ") FROM ", Table]),
    with_conn(fun(Conn) ->
        case epgsql:equery(Conn, binary_to_list(SQL), []) of
            {ok, _Cols, [{Val}]} -> {ok, Val};
            {error, Reason}      -> {error, Reason}
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

%% Transaction: wraps a function in BEGIN/COMMIT/ROLLBACK.
%% Returns {:ok, Result} on success, {:error, Reason} on failure (rolled back).
%%
%% Usage from Winn:
%%   Repo.transaction(fn() =>
%%     Repo.insert(User, %{name: "Alice"})
%%     Repo.insert(Profile, %{user_id: 1})
%%   end)
transaction(Fun) when is_function(Fun, 0) ->
    with_conn(fun(Conn) ->
        case epgsql:squery(Conn, "BEGIN") of
            {ok, [], []} ->
                try
                    Result = Fun(),
                    case epgsql:squery(Conn, "COMMIT") of
                        {ok, [], []} -> {ok, Result};
                        {error, CommitErr} -> {error, {commit_failed, CommitErr}}
                    end
                catch
                    Class:Reason:Stack ->
                        epgsql:squery(Conn, "ROLLBACK"),
                        {error, {rolled_back, Class, Reason, Stack}}
                end;
            {error, BeginErr} ->
                {error, {transaction_begin_failed, BeginErr}}
        end
    end).

with_conn(Fun) ->
    case whereis(winn_pool) of
        undefined ->
            %% No pool — direct connection (backward compatible)
            case connect() of
                {ok, Conn} ->
                    Result = Fun(Conn),
                    epgsql:close(Conn),
                    Result;
                {error, Reason} ->
                    {error, {connection_failed, Reason}}
            end;
        _Pid ->
            %% Pool available — checkout/checkin
            case winn_pool:checkout() of
                {ok, Conn} ->
                    try
                        Result = Fun(Conn),
                        winn_pool:checkin(Conn),
                        Result
                    catch Class:Reason:Stack ->
                        winn_pool:checkin(Conn),
                        erlang:raise(Class, Reason, Stack)
                    end;
                {error, pool_exhausted} ->
                    {error, {connection_failed, pool_exhausted}};
                {error, Reason} ->
                    {error, {connection_failed, Reason}}
            end
    end.

row_to_map(SchemaMod, Row) ->
    Fields = SchemaMod:'__schema__'(fields),
    Values = tuple_to_list(Row),
    maps:from_list(lists:zip(Fields, lists:sublist(Values, length(Fields)))).

row_to_map_cols(Cols, Row) ->
    ColNames = [binary_to_atom(element(2, C), utf8) || C <- Cols],
    Values   = tuple_to_list(Row),
    maps:from_list(lists:zip(ColNames, Values)).

build_where([]) ->
    {<<>>, []};
build_where(WherePairs) ->
    KVs = lists:reverse(WherePairs),
    Clauses = [iolist_to_binary([atom_to_binary(F, utf8), " = $", integer_to_binary(I)])
               || {I, {F, _}} <- lists:zip(lists:seq(1, length(KVs)), KVs)],
    Vals = [V || {_, V} <- KVs],
    {iolist_to_binary([" WHERE ", lists:join(<<" AND ">>, Clauses)]), Vals}.

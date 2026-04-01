%% winn_sqlite_tests.erl
%% Tests for SQLite adapter (#30).

-module(winn_sqlite_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Adapter configuration ──────────────────────────────────────────────────

configure_sqlite_test() ->
    winn_config:init(),
    winn_repo:configure(#{adapter => sqlite, database => "test.db"}),
    ?assertEqual(sqlite, winn_config:get(repo, adapter)),
    %% Value is a string (from Erlang map), not binary
    ?assertNotEqual(nil, winn_config:get(repo, database)).

%% ── SQL translation ($1 -> ?) ───────────────────────────────────────────────

translate_sql_test() ->
    ?assertEqual("SELECT * FROM users WHERE id = ?",
                 winn_repo_sqlite:translate_sql("SELECT * FROM users WHERE id = $1")).

translate_sql_multiple_test() ->
    ?assertEqual("INSERT INTO users (name, email) VALUES (?, ?)",
                 winn_repo_sqlite:translate_sql("INSERT INTO users (name, email) VALUES ($1, $2)")).

translate_sql_no_params_test() ->
    ?assertEqual("SELECT * FROM users",
                 winn_repo_sqlite:translate_sql("SELECT * FROM users")).

%% ── Parameter translation ───────────────────────────────────────────────────

translate_params_test() ->
    ?assertEqual([<<"hello">>, 42, 3.14],
                 winn_repo_sqlite:translate_params([<<"hello">>, 42, 3.14])).

translate_params_bool_test() ->
    ?assertEqual([1, 0],
                 winn_repo_sqlite:translate_params([true, false])).

translate_params_nil_test() ->
    ?assertEqual([nil],
                 winn_repo_sqlite:translate_params([null])).

%% ── SQLite connect/close cycle ──────────────────────────────────────────────

sqlite_connect_test() ->
    DbPath = "/tmp/winn_sqlite_test_" ++ integer_to_list(erlang:unique_integer([positive])) ++ ".db",
    {ok, Conn} = winn_repo_sqlite:connect(#{database => DbPath}),
    ?assertMatch({esqlite3, _}, Conn),
    winn_repo_sqlite:close(Conn),
    file:delete(DbPath).

%% ── End-to-end: configure SQLite from Winn ──────────────────────────────────

sqlite_from_winn_test() ->
    winn_config:init(),
    Source = "module SqliteConf\n"
             "  def run()\n"
             "    Repo.configure(%{adapter: :sqlite, database: \"test.db\"})\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST} = winn_parser:parse(Tokens),
    Transformed = winn_transform:transform(AST),
    [CoreMod] = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    try ModName:run() catch _:_ -> ok end,
    ?assertEqual(sqlite, winn_config:get(repo, adapter)).

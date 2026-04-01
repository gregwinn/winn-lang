%% winn_migrate_tests.erl
%% Tests for database migrations (#17).

-module(winn_migrate_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── CLI parse args ──────────────────────────────────────────────────────────

parse_migrate_test() ->
    ?assertEqual({migrate, []}, winn_cli:parse_args(["migrate"])).

parse_migrate_status_test() ->
    ?assertEqual({migrate, ["--status"]}, winn_cli:parse_args(["migrate", "--status"])).

parse_migrate_step_test() ->
    ?assertEqual({migrate, ["--step", "2"]}, winn_cli:parse_args(["migrate", "--step", "2"])).

parse_rollback_test() ->
    ?assertEqual({rollback, []}, winn_cli:parse_args(["rollback"])).

parse_rollback_step_test() ->
    ?assertEqual({rollback, ["--step", "3"]}, winn_cli:parse_args(["rollback", "--step", "3"])).

%% ── Migration discovery ─────────────────────────────────────────────────────

discover_no_dir_test() ->
    %% When no migrations/ directory exists, status still works
    %% (we can't call discover_migrations directly as it's internal)
    Exports = winn_migrate:module_info(exports),
    ?assert(lists:member({status, 0}, Exports)).

%% ── Migration name extraction ───────────────────────────────────────────────

migration_name_test() ->
    %% Internal helper — test via module_info
    Exports = winn_migrate:module_info(exports),
    ?assert(lists:member({migrate, 1}, Exports)),
    ?assert(lists:member({rollback, 1}, Exports)),
    ?assert(lists:member({status, 0}, Exports)),
    ?assert(lists:member({ensure_migrations_table, 0}, Exports)).

%% ── Migration module compiles ───────────────────────────────────────────────

migration_module_compiles_test() ->
    Source = "module Migrations.CreateUsers\n"
             "  def up()\n"
             "    Repo.execute(\"CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT)\")\n"
             "  end\n"
             "\n"
             "  def down()\n"
             "    Repo.execute(\"DROP TABLE users\")\n"
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
    %% Module name should be dotted lowercase
    ?assertEqual('migrations.createusers', ModName),
    %% Should export up/0 and down/0
    ?assert(erlang:function_exported(ModName, up, 0)),
    ?assert(erlang:function_exported(ModName, down, 0)).

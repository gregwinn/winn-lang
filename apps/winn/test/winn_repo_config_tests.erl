%% winn_repo_config_tests.erl
%% Tests for Repo.configure and db_config reading from Config ETS.

-module(winn_repo_config_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Setup/teardown ──────────────────────────────────────────────────────────

setup() ->
    winn_config:init(),
    %% Clear any repo config keys
    lists:foreach(fun(Key) ->
        winn_config:put(repo, Key, nil)
    end, [host, port, database, username, password]).

%% ── Repo.configure stores values in Config ETS ─────────────────────────────

configure_sets_values_test() ->
    setup(),
    ok = winn_repo:configure(#{
        host => <<"db.example.com">>,
        port => 5433,
        database => <<"my_app">>,
        username => <<"admin">>,
        password => <<"secret">>
    }),
    ?assertEqual(<<"db.example.com">>, winn_config:get(repo, host)),
    ?assertEqual(5433, winn_config:get(repo, port)),
    ?assertEqual(<<"my_app">>, winn_config:get(repo, database)),
    ?assertEqual(<<"admin">>, winn_config:get(repo, username)),
    ?assertEqual(<<"secret">>, winn_config:get(repo, password)).

%% ── Partial configure merges with defaults ───────────────────────────────────

partial_configure_test() ->
    setup(),
    ok = winn_repo:configure(#{host => <<"custom-host">>}),
    ?assertEqual(<<"custom-host">>, winn_config:get(repo, host)),
    %% Unset keys remain nil in ETS (defaults applied at db_config level)
    ?assertEqual(nil, winn_config:get(repo, port)).

%% ── Multiple configures overwrite ───────────────────────────────────────────

reconfigure_test() ->
    setup(),
    ok = winn_repo:configure(#{database => <<"first_db">>}),
    ok = winn_repo:configure(#{database => <<"second_db">>}),
    ?assertEqual(<<"second_db">>, winn_config:get(repo, database)).

%% ── End-to-end: Repo.configure from Winn source ────────────────────────────

configure_from_winn_test() ->
    setup(),
    Source = "module RepoConfTest\n"
             "  def run()\n"
             "    Repo.configure(%{host: \"myhost\", database: \"mydb\"})\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ok = ModName:run(),
    ?assertEqual(<<"myhost">>, winn_config:get(repo, host)),
    ?assertEqual(<<"mydb">>, winn_config:get(repo, database)).

%% ── Binary → charlist normalization for epgsql (#145) ──────────────────────

normalize_epgsql_config_converts_binaries_to_charlists_test() ->
    Config = #{
        host     => <<"postgresql.databases.svc.cluster.local">>,
        port     => 5432,
        database => <<"myapp">>,
        username => <<"postgres">>,
        password => <<"secret">>
    },
    Normalized = winn_repo:normalize_epgsql_config(Config),
    ?assertEqual("postgresql.databases.svc.cluster.local", maps:get(host, Normalized)),
    ?assertEqual(5432, maps:get(port, Normalized)),
    ?assertEqual("myapp", maps:get(database, Normalized)),
    ?assertEqual("postgres", maps:get(username, Normalized)),
    ?assertEqual("secret", maps:get(password, Normalized)).

normalize_epgsql_config_passes_through_charlists_test() ->
    Config = #{
        host     => "localhost",
        port     => 5432,
        database => "winn_dev",
        username => "postgres",
        password => ""
    },
    Normalized = winn_repo:normalize_epgsql_config(Config),
    ?assertEqual("localhost", maps:get(host, Normalized)),
    ?assertEqual("winn_dev", maps:get(database, Normalized)),
    ?assertEqual("postgres", maps:get(username, Normalized)),
    ?assertEqual("", maps:get(password, Normalized)).

normalize_epgsql_config_handles_atom_host_test() ->
    Config = #{
        host     => localhost,
        port     => 5432,
        database => <<"mydb">>,
        username => <<"u">>,
        password => <<"p">>
    },
    Normalized = winn_repo:normalize_epgsql_config(Config),
    ?assertEqual("localhost", maps:get(host, Normalized)).

normalize_epgsql_config_preserves_extra_keys_test() ->
    %% epgsql supports ssl, ssl_opts, timeout, connect_timeout, etc.
    %% The normalizer must not drop them.
    Config = #{
        host          => <<"db.example.com">>,
        port          => 5432,
        database      => <<"mydb">>,
        username      => <<"u">>,
        password      => <<"p">>,
        ssl           => required,
        ssl_opts      => [{verify, verify_peer}],
        timeout       => 10000
    },
    Normalized = winn_repo:normalize_epgsql_config(Config),
    ?assertEqual(required, maps:get(ssl, Normalized)),
    ?assertEqual([{verify, verify_peer}], maps:get(ssl_opts, Normalized)),
    ?assertEqual(10000, maps:get(timeout, Normalized)),
    ?assertEqual("db.example.com", maps:get(host, Normalized)).

normalize_epgsql_config_tolerates_missing_keys_test() ->
    %% Exported function: callers may pass partial maps. Should not crash.
    Config = #{host => <<"db.example.com">>, port => 5432},
    Normalized = winn_repo:normalize_epgsql_config(Config),
    ?assertEqual("db.example.com", maps:get(host, Normalized)),
    ?assertEqual(5432, maps:get(port, Normalized)),
    ?assertEqual(error, maps:find(database, Normalized)).

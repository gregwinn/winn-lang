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

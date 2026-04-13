%% winn_pool_tests.erl
%% Tests for connection pool (#41).
%% Since we can't connect to a real DB in unit tests, we test:
%% - Pool GenServer lifecycle
%% - Repo.configure with pool_size
%% - Repo.pool_status
%% - with_conn fallback (no pool = direct connection)

-module(winn_pool_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Repo.configure stores pool_size ─────────────────────────────────────────

configure_pool_size_test() ->
    winn_config:init(),
    winn_repo:configure(#{pool_size => 10}),
    ?assertEqual(10, winn_config:get(repo, pool_size)).

%% ── pool_status when pool not started ───────────────────────────────────────

pool_not_started_test() ->
    %% Ensure pool is not running. gen_server:stop may return with a
    %% non-normal reason when the pool's linked connection attempts
    %% failed (econnrefused in CI with no DB) — swallow those since we
    %% only care that the process is gone afterwards.
    case whereis(winn_pool) of
        undefined -> ok;
        Pid ->
            try gen_server:stop(Pid, normal, 1000)
            catch exit:_ -> ok
            end,
            %% Wait for the name to actually be released
            wait_for_unregister(winn_pool, 20)
    end,
    ?assertEqual({error, pool_not_started}, winn_repo:pool_status()).

wait_for_unregister(_Name, 0) -> timeout;
wait_for_unregister(Name, N) ->
    case whereis(Name) of
        undefined -> ok;
        _ -> timer:sleep(50), wait_for_unregister(Name, N - 1)
    end.

%% ── Repo exports pool functions ─────────────────────────────────────────────

repo_exports_pool_fns_test() ->
    Exports = winn_repo:module_info(exports),
    ?assert(lists:member({start_pool, 0}, Exports)),
    ?assert(lists:member({pool_status, 0}, Exports)),
    ?assert(lists:member({configure, 1}, Exports)).

%% ── End-to-end: configure from Winn source ──────────────────────────────────

configure_pool_from_winn_test() ->
    winn_config:init(),
    Source = "module PoolConfTest\n"
             "  def run()\n"
             "    Repo.configure(%{host: \"localhost\", pool_size: 3})\n"
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
    %% Run will try to start pool (will fail since no DB, but config should be set)
    try ModName:run() catch _:_ -> ok end,
    ?assertEqual(3, winn_config:get(repo, pool_size)),
    ?assertEqual(<<"localhost">>, winn_config:get(repo, host)).

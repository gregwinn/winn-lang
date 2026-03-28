%% winn_deps_tests.erl — N3: Dependency management tests.
%% Tests rebar.config reading/writing without running rebar3.

-module(winn_deps_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Setup/teardown with temp rebar.config ───────────────────────────────

setup_config(Content) ->
    file:write_file("rebar.config.test_backup", Content),
    file:write_file("rebar.config", Content).

restore_config() ->
    case file:read_file("rebar.config.test_backup") of
        {ok, Bin} ->
            file:write_file("rebar.config", Bin),
            file:delete("rebar.config.test_backup");
        _ -> ok
    end.

%% ── Read tests ──────────────────────────────────────────────────────────

read_deps_test() ->
    %% Save current config, test, restore
    {ok, OrigBin} = file:read_file("rebar.config"),
    setup_config("{deps, [{foo, \"1.0\"}, {bar, \"2.0\"}]}.\n"),
    {ok, Deps} = winn_deps:read_deps_for_test(),
    ?assertEqual([{foo, "1.0"}, {bar, "2.0"}], Deps),
    file:write_file("rebar.config", OrigBin).

read_empty_deps_test() ->
    {ok, OrigBin} = file:read_file("rebar.config"),
    setup_config("{deps, []}.\n"),
    {ok, Deps} = winn_deps:read_deps_for_test(),
    ?assertEqual([], Deps),
    file:write_file("rebar.config", OrigBin).

read_no_deps_key_test() ->
    {ok, OrigBin} = file:read_file("rebar.config"),
    setup_config("{erl_opts, [debug_info]}.\n"),
    {ok, Deps} = winn_deps:read_deps_for_test(),
    ?assertEqual([], Deps),
    file:write_file("rebar.config", OrigBin).

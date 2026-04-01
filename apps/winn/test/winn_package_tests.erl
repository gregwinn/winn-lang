%% winn_package_tests.erl
%% Tests for the package system (#88).

-module(winn_package_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── CLI parse args ──────────────────────────────────────────────────────────

parse_add_test() ->
    ?assertEqual({pkg_add, ["redis"]}, winn_cli:parse_args(["add", "redis"])).

parse_add_github_test() ->
    ?assertEqual({pkg_add, ["github:user/winn-stripe"]},
                 winn_cli:parse_args(["add", "github:user/winn-stripe"])).

parse_remove_test() ->
    ?assertEqual({pkg_remove, ["redis"]}, winn_cli:parse_args(["remove", "redis"])).

parse_packages_test() ->
    ?assertEqual(pkg_list, winn_cli:parse_args(["packages"])).

parse_install_test() ->
    ?assertEqual(pkg_install, winn_cli:parse_args(["install"])).

%% ── Manifest reading ────────────────────────────────────────────────────────

read_manifest_test() ->
    TmpDir = "/tmp/winn_pkg_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(TmpDir),
    ManifestPath = TmpDir ++ "/package.json",
    file:write_file(ManifestPath, <<"{\"name\": \"test\", \"version\": \"1.0.0\", \"module\": \"Test\"}">>),
    {ok, Manifest} = winn_package:read_manifest(TmpDir),
    ?assertEqual(<<"test">>, maps:get(<<"name">>, Manifest)),
    ?assertEqual(<<"1.0.0">>, maps:get(<<"version">>, Manifest)),
    ?assertEqual(<<"Test">>, maps:get(<<"module">>, Manifest)),
    os:cmd("rm -rf " ++ TmpDir).

%% ── Module mappings ─────────────────────────────────────────────────────────

module_mappings_empty_test() ->
    %% When no packages installed, mappings is empty
    ?assertEqual([], winn_package:get_module_mappings()).

%% ── Scaffold includes package.json ──────────────────────────────────────────

scaffold_package_json_test() ->
    TmpDir = "/tmp/winn_scaffold_pkg_" ++ integer_to_list(erlang:unique_integer([positive])),
    winn_cli:scaffold(TmpDir),
    ?assert(filelib:is_file(TmpDir ++ "/package.json")),
    {ok, Content} = file:read_file(TmpDir ++ "/package.json"),
    ?assert(binary:match(Content, <<"packages">>) =/= nomatch),
    os:cmd("rm -rf " ++ TmpDir).

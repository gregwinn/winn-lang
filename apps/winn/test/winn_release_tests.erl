%% winn_release_tests.erl
%% Tests for deployment / release (#18).

-module(winn_release_tests).
-include_lib("eunit/include/eunit.hrl").

parse_release_test() ->
    ?assertEqual({release, []}, winn_cli:parse_args(["release"])).

parse_release_docker_test() ->
    ?assertEqual({release, ["--docker"]}, winn_cli:parse_args(["release", "--docker"])).

dockerfile_generation_test() ->
    OldDir = file:get_cwd(),
    TmpDir = "/tmp/winn_release_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(TmpDir),
    file:set_cwd(TmpDir),

    %% Generate Dockerfile
    winn_cli:generate_dockerfile(),

    ?assert(filelib:is_file("Dockerfile")),
    {ok, Content} = file:read_file("Dockerfile"),
    ?assert(binary:match(Content, <<"FROM erlang">>) =/= nomatch),
    ?assert(binary:match(Content, <<"rebar3">>) =/= nomatch),
    ?assert(binary:match(Content, <<"EXPOSE 4000">>) =/= nomatch),

    file:set_cwd(element(2, OldDir)),
    os:cmd("rm -rf " ++ TmpDir).

dockerfile_no_overwrite_test() ->
    OldDir = file:get_cwd(),
    TmpDir = "/tmp/winn_release_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(TmpDir),
    file:set_cwd(TmpDir),

    %% Create existing Dockerfile
    file:write_file("Dockerfile", "existing"),
    winn_cli:generate_dockerfile(),

    %% Should NOT overwrite
    {ok, Content} = file:read_file("Dockerfile"),
    ?assertEqual(<<"existing">>, Content),

    file:set_cwd(element(2, OldDir)),
    os:cmd("rm -rf " ++ TmpDir).

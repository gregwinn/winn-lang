%% winn_generator_tests.erl
%% Tests for code generators (#74).

-module(winn_generator_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── CLI parse args ──────────────────────────────────────────────────────────

parse_create_model_args_test() ->
    ?assertEqual({create, ["model", "User", "name:string"]},
                 winn_cli:parse_args(["create", "model", "User", "name:string"])).

parse_c_shorthand_maps_to_create_test() ->
    ?assertEqual({create, ["model", "User"]},
                 winn_cli:parse_args(["c", "model", "User"])).

parse_create_scaffold_with_fields_test() ->
    ?assertEqual({create, ["scaffold", "Post", "title:string", "body:text"]},
                 winn_cli:parse_args(["create", "scaffold", "Post", "title:string", "body:text"])).

%% ── Field parsing ───────────────────────────────────────────────────────────

parse_fields_splits_colon_pairs_test() ->
    ?assertEqual([{"name", "string"}, {"age", "integer"}],
                 winn_generator:parse_fields(["name:string", "age:integer"])).

parse_fields_returns_empty_for_no_args_test() ->
    ?assertEqual([], winn_generator:parse_fields([])).

parse_fields_skips_args_without_colon_test() ->
    ?assertEqual([{"name", "string"}],
                 winn_generator:parse_fields(["name:string", "invalid"])).

%% ── Model generator ────────────────────────────────────────────────────────

model_generates_schema_file_in_models_dir_test() ->
    %% Generate in a temp directory
    OldDir = file:get_cwd(),
    TmpDir = "/tmp/winn_gen_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(TmpDir ++ "/src/models"),
    file:set_cwd(TmpDir),

    winn_generator:generate(model, ["User", "name:string", "email:string"]),

    {ok, Content} = file:read_file("src/models/user.winn"),
    ?assert(binary:match(Content, <<"module User">>) =/= nomatch),
    ?assert(binary:match(Content, <<"use Winn.Schema">>) =/= nomatch),
    ?assert(binary:match(Content, <<"schema \"users\"">>) =/= nomatch),
    ?assert(binary:match(Content, <<"field :name, :string">>) =/= nomatch),
    ?assert(binary:match(Content, <<"field :email, :string">>) =/= nomatch),

    %% Cleanup
    file:set_cwd(element(2, OldDir)),
    os:cmd("rm -rf " ++ TmpDir).

%% ── Task generator ─────────────────────────────────────────────────────────

task_generates_file_in_tasks_dir_test() ->
    OldDir = file:get_cwd(),
    TmpDir = "/tmp/winn_gen_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(TmpDir ++ "/src/tasks"),
    file:set_cwd(TmpDir),

    winn_generator:generate(task, ["db:seed"]),

    {ok, Content} = file:read_file("src/tasks/db_seed.winn"),
    ?assert(binary:match(Content, <<"module Tasks.Db.Seed">>) =/= nomatch),
    ?assert(binary:match(Content, <<"use Winn.Task">>) =/= nomatch),
    ?assert(binary:match(Content, <<"def run(args)">>) =/= nomatch),

    file:set_cwd(element(2, OldDir)),
    os:cmd("rm -rf " ++ TmpDir).

%% ── Router generator ───────────────────────────────────────────────────────

router_generates_controller_in_controllers_dir_test() ->
    OldDir = file:get_cwd(),
    TmpDir = "/tmp/winn_gen_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(TmpDir ++ "/src/controllers"),
    file:set_cwd(TmpDir),

    winn_generator:generate(router, ["Api"]),

    {ok, Content} = file:read_file("src/controllers/api_controller.winn"),
    ?assert(binary:match(Content, <<"module ApiController">>) =/= nomatch),
    ?assert(binary:match(Content, <<"use Winn.Router">>) =/= nomatch),
    ?assert(binary:match(Content, <<"def routes()">>) =/= nomatch),

    file:set_cwd(element(2, OldDir)),
    os:cmd("rm -rf " ++ TmpDir).

%% ── Migration generator ────────────────────────────────────────────────────

migration_generates_timestamped_file_in_db_dir_test() ->
    OldDir = file:get_cwd(),
    TmpDir = "/tmp/winn_gen_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(TmpDir ++ "/db/migrations"),
    file:set_cwd(TmpDir),

    winn_generator:generate(migration, ["CreateUsers", "name:string", "email:string"]),

    Files = filelib:wildcard("db/migrations/*.winn"),
    ?assertEqual(1, length(Files)),
    {ok, Content} = file:read_file(hd(Files)),
    ?assert(binary:match(Content, <<"module Migrations.CreateUsers">>) =/= nomatch),
    ?assert(binary:match(Content, <<"def up()">>) =/= nomatch),
    ?assert(binary:match(Content, <<"CREATE TABLE">>) =/= nomatch),

    file:set_cwd(element(2, OldDir)),
    os:cmd("rm -rf " ++ TmpDir).

%% ── Scaffold generator ─────────────────────────────────────────────────────

scaffold_generates_model_controller_and_test_test() ->
    OldDir = file:get_cwd(),
    TmpDir = "/tmp/winn_gen_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(TmpDir ++ "/src/models"),
    ok = filelib:ensure_path(TmpDir ++ "/src/controllers"),
    ok = filelib:ensure_path(TmpDir ++ "/test"),
    file:set_cwd(TmpDir),

    winn_generator:generate(scaffold, ["Post", "title:string", "body:text"]),

    ?assert(filelib:is_file("src/models/post.winn")),
    ?assert(filelib:is_file("src/controllers/post_controller.winn")),
    ?assert(filelib:is_file("test/post_test.winn")),

    {ok, ControllerContent} = file:read_file("src/controllers/post_controller.winn"),
    ?assert(binary:match(ControllerContent, <<"PostController">>) =/= nomatch),
    ?assert(binary:match(ControllerContent, <<"Post.all()">>) =/= nomatch),

    file:set_cwd(element(2, OldDir)),
    os:cmd("rm -rf " ++ TmpDir).

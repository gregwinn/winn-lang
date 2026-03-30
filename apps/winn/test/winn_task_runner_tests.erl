%% winn_task_runner_tests.erl
%% Tests for the CLI task runner (#16).

-module(winn_task_runner_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Parse args ──────────────────────────────────────────────────────────────

parse_task_test() ->
    ?assertEqual({task, ["db.migrate"]}, winn_cli:parse_args(["task", "db.migrate"])).

parse_task_with_args_test() ->
    ?assertEqual({task, ["db.seed", "--file", "data.csv"]},
                 winn_cli:parse_args(["task", "db.seed", "--file", "data.csv"])).

parse_task_no_name_test() ->
    ?assertEqual({task, []}, winn_cli:parse_args(["task"])).

%% ── Task name to module mapping ─────────────────────────────────────────────

task_name_mapping_test() ->
    ?assertEqual('tasks.db.migrate', winn_cli:task_name_to_module("db.migrate")).

task_name_simple_test() ->
    ?assertEqual('tasks.hello', winn_cli:task_name_to_module("hello")).

task_name_nested_test() ->
    ?assertEqual('tasks.db.seed.users', winn_cli:task_name_to_module("db.seed.users")).

%% ── End-to-end: compile and run a Winn task ─────────────────────────────────

task_e2e_test() ->
    %% Create a task module, compile it, load it, call run/1
    Source = "module Tasks.Hello\n"
             "  use Winn.Task\n"
             "\n"
             "  def run(args)\n"
             "    :ok\n"
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

    %% Module should be 'tasks.hello' (lowercased dotted name)
    ?assertEqual('tasks.hello', ModName),

    %% Should have run/1 exported
    ?assert(erlang:function_exported(ModName, run, 1)),

    %% Should have winn_task behaviour
    Attrs = ModName:module_info(attributes),
    Behaviours = proplists:get_value(behaviour, Attrs, []),
    ?assert(lists:member(winn_task, Behaviours)),

    %% Calling run should work
    ?assertEqual(ok, ModName:run([])).

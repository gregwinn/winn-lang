%% winn_m3_tests.erl — M3: Application Startup tests.

-module(winn_m3_tests).
-include_lib("eunit/include/eunit.hrl").

compile_and_load(Source) ->
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── Transform tests ─────────────────────────────────────────────────────

use_application_adds_behaviour_test() ->
    Src = "module MyApp\n  use Winn.Application\n\n  def start(type, args)\n    :ok\n  end\nend\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, AST} = winn_parser:parse(Tokens),
    [{module, _, 'MyApp', Body}] = winn_transform:transform(AST),
    %% First element should be the behaviour attribute.
    ?assertMatch({behaviour_attr, _, application}, hd(Body)).

%% ── E2E compilation test ────────────────────────────────────────────────

e2e_application_compiles_test() ->
    Src = "module TestApp\n  use Winn.Application\n\n  def start(type, args)\n    :ok\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assert(erlang:function_exported(Mod, start, 2)).

use_task_adds_behaviour_test() ->
    Src = "module MyTask\n  use Winn.Task\n\n  def run(args)\n    :ok\n  end\nend\n",
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, AST} = winn_parser:parse(Tokens),
    [{module, _, 'MyTask', Body}] = winn_transform:transform(AST),
    ?assertMatch({behaviour_attr, _, winn_task}, hd(Body)).

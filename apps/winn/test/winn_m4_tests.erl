%% winn_m4_tests.erl — M4: Task/Async tests.

-module(winn_m4_tests).
-include_lib("eunit/include/eunit.hrl").

compile_and_load(Source) ->
    {ok, Tokens, _} = winn_lexer:string(Source),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── Direct runtime tests ────────────────────────────────────────────────

spawn_returns_pid_test() ->
    Pid = winn_task:spawn(fun() -> ok end),
    ?assert(is_pid(Pid)).

async_await_test() ->
    Handle = winn_task:async(fun() -> 42 end),
    ?assertEqual(42, winn_task:await(Handle)).

async_await_complex_test() ->
    Handle = winn_task:async(fun() -> lists:seq(1, 5) end),
    ?assertEqual([1,2,3,4,5], winn_task:await(Handle)).

await_timeout_test() ->
    Handle = winn_task:async(fun() -> timer:sleep(10000), ok end),
    ?assertEqual({error, timeout}, winn_task:await(Handle, 50)).

async_all_test() ->
    Results = winn_task:async_all([1, 2, 3], fun(N) -> N * 10 end),
    ?assertEqual([10, 20, 30], Results).

async_all_preserves_order_test() ->
    %% Even with varying delays, results should be in input order.
    Results = winn_task:async_all([3, 1, 2], fun(N) ->
        timer:sleep(N * 10),
        N
    end),
    ?assertEqual([3, 1, 2], Results).

%% ── E2E tests ───────────────────────────────────────────────────────────

e2e_codegen_test() ->
    %% Verify Task.async_all compiles via the codegen path.
    Src = "module TaskTest\n  def run(list, f)\n    Task.async_all(list, f)\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assert(erlang:function_exported(Mod, run, 2)).

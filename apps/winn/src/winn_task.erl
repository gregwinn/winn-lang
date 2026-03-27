%% winn_task.erl
%% M4 — Task/Async for Winn programs.
%%
%% Task.spawn(Fun)          -> pid (fire and forget)
%% Task.async(Fun)          -> {pid, ref} (async handle)
%% Task.await(Handle)       -> result (blocks, 5s default timeout)
%% Task.await(Handle, Ms)   -> result (blocks with timeout)
%% Task.async_all(List, Fun) -> [result] (parallel map)

-module(winn_task).
-export([spawn/1, async/1, await/1, await/2, async_all/2]).

%% Fire and forget — spawns a process, returns its pid.
spawn(Fun) when is_function(Fun, 0) ->
    erlang:spawn(Fun).

%% Async — spawns a process that sends result back.
%% Returns {Pid, Ref} as handle.
async(Fun) when is_function(Fun, 0) ->
    Parent = self(),
    Ref = make_ref(),
    Pid = erlang:spawn(fun() ->
        Result = Fun(),
        Parent ! {task_result, Ref, Result}
    end),
    {Pid, Ref}.

%% Await with default 5 second timeout.
await({_Pid, Ref}) ->
    await({_Pid, Ref}, 5000).

%% Await with explicit timeout in milliseconds.
await({_Pid, Ref}, Timeout) when is_integer(Timeout) ->
    receive
        {task_result, Ref, Result} -> Result
    after Timeout ->
        {error, timeout}
    end.

%% Parallel map — runs Fun on each element concurrently, collects results in order.
async_all(List, Fun) when is_list(List), is_function(Fun, 1) ->
    Handles = [begin
        F = fun() -> Fun(Elem) end,
        async(F)
    end || Elem <- List],
    [await(H) || H <- Handles].

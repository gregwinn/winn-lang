-module(winn_pipeline_tests).
-include_lib("eunit/include/eunit.hrl").

%% Helpers invoked by compiled pipeline modules as `Winn_pipeline_tests.*`.
-export([record_batch/1, process_double/1, sleepy/1, flaky/1, forever/0]).

%% Tests for the `pipeline` keyword: Broadway-shape supervised dataflow.
%%
%% Each test compiles a Winn pipeline definition, spins up a tiny
%% in-memory producer pre-compiled in Erlang, starts the pipeline, and
%% verifies end-to-end behaviour. A shared fixture (an ETS-backed list
%% producer) stands in for the fleet-delivery AMQP source.

%% ── Helpers ───────────────────────────────────────────────────────────────

compile_and_load(Source) ->
    {ok, Tokens, _} = winn_lexer:string(Source),
    Filtered = winn_newline_filter:filter(Tokens),
    {ok, AST} = winn_parser:parse(Filtered),
    Transformed = winn_transform:transform(AST),
    [CoreMod] = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

ensure_producer_loaded() ->
    case code:is_loaded(pipetestproducer) of
        {file, _} -> ok;
        _ ->
            compile_producer(),
            ok
    end.

%% Dynamically compile the in-memory producer Erlang module on first use.
compile_producer() ->
    Src = producer_source(),
    {ok, Forms} = parse_erl_forms(Src),
    {ok, Mod, Bin} = compile:forms(Forms, [return_errors]),
    code:purge(Mod),
    {module, Mod} = code:load_binary(Mod, "pipetestproducer.erl", Bin),
    ok.

parse_erl_forms(Src) ->
    {ok, Tokens, _} = erl_scan:string(Src),
    split_forms(Tokens, [], []).

split_forms([], [], Acc) ->
    {ok, lists:reverse(Acc)};
split_forms([], Buf, Acc) ->
    {ok, Form} = erl_parse:parse_form(lists:reverse(Buf)),
    {ok, lists:reverse([Form | Acc])};
split_forms([Tok = {dot, _} | Rest], Buf, Acc) ->
    {ok, Form} = erl_parse:parse_form(lists:reverse([Tok | Buf])),
    split_forms(Rest, [], [Form | Acc]);
split_forms([Tok | Rest], Buf, Acc) ->
    split_forms(Rest, [Tok | Buf], Acc).

producer_source() ->
    "-module(pipetestproducer).\n"
    "-export([init/1, pull/2, ack/3, terminate/2, set_items/2, wait_acked/2, acked/1]).\n"
    "init(Opts) ->\n"
    "    Name = maps:get(fixture, Opts, default),\n"
    "    case ets:whereis(Name) of\n"
    "        undefined -> ets:new(Name, [public, set, named_table]);\n"
    "        _ -> ok\n"
    "    end,\n"
    "    ensure_default(Name, items, []),\n"
    "    ensure_default(Name, acked, 0),\n"
    "    ensure_default(Name, nacks, 0),\n"
    "    {ok, Name}.\n"
    "ensure_default(T, K, V) ->\n"
    "    case ets:lookup(T, K) of\n"
    "        [] -> ets:insert(T, {K, V});\n"
    "        _  -> ok\n"
    "    end.\n"
    "pull(T, Demand) ->\n"
    "    [{items, Items}] = ets:lookup(T, items),\n"
    "    Take = min(Demand, length(Items)),\n"
    "    {Head, Rest} = lists:split(Take, Items),\n"
    "    ets:insert(T, {items, Rest}),\n"
    "    {ok, Head, T}.\n"
    "ack(T, _Msg, ack) ->\n"
    "    ets:update_counter(T, acked, 1),\n"
    "    T;\n"
    "ack(T, _Msg, {nack, _}) ->\n"
    "    ets:update_counter(T, nacks, 1),\n"
    "    T.\n"
    "terminate(_T, _R) -> ok.\n"
    "set_items(Name, Items) ->\n"
    "    case ets:whereis(Name) of\n"
    "        undefined -> ets:new(Name, [public, set, named_table]);\n"
    "        _ -> ok\n"
    "    end,\n"
    "    ensure_default(Name, items, []),\n"
    "    ensure_default(Name, acked, 0),\n"
    "    ensure_default(Name, nacks, 0),\n"
    "    ets:insert(Name, {items, Items}),\n"
    "    ok.\n"
    "acked(Name) ->\n"
    "    case ets:lookup(Name, acked) of\n"
    "        [{acked, N}] -> N;\n"
    "        _ -> 0\n"
    "    end.\n"
    "wait_acked(Name, Target) -> wait_acked(Name, Target, 200).\n"
    "wait_acked(Name, Target, 0) -> {timeout, acked(Name), Target};\n"
    "wait_acked(Name, Target, N) ->\n"
    "    case acked(Name) of\n"
    "        V when V >= Target -> {ok, V};\n"
    "        _ -> timer:sleep(20), wait_acked(Name, Target, N - 1)\n"
    "    end.\n".

%% Collector process for observing batcher output across tests.
start_collector() ->
    case ets:whereis(pipetest_sink) of
        undefined -> ets:new(pipetest_sink, [public, set, named_table]);
        _ -> ok
    end,
    ets:insert(pipetest_sink, {batches, []}),
    ets:insert(pipetest_sink, {items, []}),
    ok.

sink_batches() ->
    case ets:lookup(pipetest_sink, batches) of
        [{batches, B}] -> lists:reverse(B);
        _ -> []
    end.

sink_items() ->
    case ets:lookup(pipetest_sink, items) of
        [{items, I}] -> lists:reverse(I);
        _ -> []
    end.

record_batch(Batch) ->
    [{batches, Prev}] = ets:lookup(pipetest_sink, batches),
    ets:insert(pipetest_sink, {batches, [Batch | Prev]}),
    [{items, PItems}] = ets:lookup(pipetest_sink, items),
    ets:insert(pipetest_sink, {items, lists:reverse(Batch) ++ PItems}),
    ok.

process_double(N) when is_integer(N) -> N * 2.

start_and_wait(PipelineMod, Fixture, Target) ->
    process_flag(trap_exit, true),
    {ok, Sup} = PipelineMod:start_link(),
    true = unlink(Sup),
    Result = pipetestproducer:wait_acked(Fixture, Target),
    stop_and_wait(PipelineMod),
    Result.

stop_and_wait(PipelineMod) ->
    case whereis(PipelineMod) of
        undefined -> ok;
        Pid ->
            MRef = erlang:monitor(process, Pid),
            PipelineMod:stop(),
            receive
                {'DOWN', MRef, process, Pid, _} -> ok
            after 5000 ->
                erlang:demonitor(MRef, [flush]),
                exit(Pid, kill),
                ok
            end
    end.

setup_fixture(Fixture, Items) ->
    ensure_producer_loaded(),
    start_collector(),
    pipetestproducer:set_items(Fixture, Items),
    ok.

%% ── Tests ─────────────────────────────────────────────────────────────────

%% 1. Compiles — smoke test: pipeline source produces a loadable module.
compiles_test() ->
    Mod = compile_and_load(
        "pipeline Compiles1\n"
        "  producer :src, source: PipetestProducer\n"
        "  processor :work, concurrency: 1 do |m| m end\n"
        "end\n"),
    Exports = Mod:module_info(exports),
    ?assert(lists:member({start_link, 0}, Exports)),
    ?assert(lists:member({stop, 0}, Exports)),
    ?assert(lists:member({stats, 0}, Exports)),
    ?assert(lists:member({init, 1}, Exports)),
    ?assert(lists:member({pipeline_spec, 0}, Exports)),
    Spec = Mod:pipeline_spec(),
    ?assertMatch(#{producer := _, processor := _}, Spec).

%% 2. End-to-end — 30 messages through pipeline with batcher, assert all arrive.
end_to_end_test() ->
    setup_fixture(fixture_e2e, lists:seq(1, 30)),
    Mod = compile_and_load(
        "pipeline EndToEnd1\n"
        "  producer :src, source: PipetestProducer, fixture: :fixture_e2e, prefetch: 10\n"
        "  processor :work, concurrency: 2 do |n| Winn_pipeline_tests.process_double(n) end\n"
        "  batcher :sink, size: 5, timeout: 500 do |batch| Winn_pipeline_tests.record_batch(batch) end\n"
        "end\n"),
    {ok, _} = start_and_wait(Mod, fixture_e2e, 30),
    timer:sleep(200),
    Items = sink_items(),
    Expected = [N * 2 || N <- lists:seq(1, 30)],
    ?assertEqual(lists:sort(Expected), lists:sort(Items)),
    ok.

%% 3. Concurrency — 20 messages through 4 workers; each worker takes 50ms;
%%    must complete noticeably faster than serial (20*50=1000ms).
concurrency_test() ->
    setup_fixture(fixture_conc, lists:seq(1, 20)),
    Mod = compile_and_load(
        "pipeline Concur1\n"
        "  producer :src, source: PipetestProducer, fixture: :fixture_conc, prefetch: 8\n"
        "  processor :work, concurrency: 4 do |n|\n"
        "    Winn_pipeline_tests.sleepy(n)\n"
        "  end\n"
        "end\n"),
    T0 = erlang:monotonic_time(millisecond),
    {ok, _} = start_and_wait(Mod, fixture_conc, 20),
    Elapsed = erlang:monotonic_time(millisecond) - T0,
    ?assert(Elapsed < 900, {too_slow, Elapsed}),
    ok.

sleepy(N) -> timer:sleep(50), N.

%% 4. Retry — handler fails the first 2 attempts, succeeds on 3rd.
retry_test() ->
    setup_fixture(fixture_retry, [1, 2, 3]),
    ensure_retry_counter(),
    Mod = compile_and_load(
        "pipeline Retry1\n"
        "  producer :src, source: PipetestProducer, fixture: :fixture_retry, prefetch: 5\n"
        "  processor :work, concurrency: 1, retry: 3 do |n|\n"
        "    Winn_pipeline_tests.flaky(n)\n"
        "  end\n"
        "end\n"),
    {ok, _} = start_and_wait(Mod, fixture_retry, 3),
    %% Every message is attempted 3 times; 3 messages * 3 attempts = 9 total calls.
    ?assertEqual(9, retry_total_calls()),
    ok.

ensure_retry_counter() ->
    case ets:whereis(pipetest_retry) of
        undefined -> ets:new(pipetest_retry, [public, set, named_table]);
        _ -> ok
    end,
    ets:insert(pipetest_retry, {calls, 0}),
    ets:insert(pipetest_retry, {fail_count, 2}),
    ok.

retry_total_calls() ->
    [{calls, N}] = ets:lookup(pipetest_retry, calls),
    N.

flaky(N) ->
    [{calls, C}] = ets:lookup(pipetest_retry, calls),
    ets:insert(pipetest_retry, {calls, C + 1}),
    %% Fail first 2 attempts per *instance* of the pipeline (not per message);
    %% we just simulate transient errors and let retry resolve them.
    Phase = (C rem 3),
    case Phase of
        2 -> N;  %% 3rd attempt (indices 0,1,2) succeeds
        _ -> erlang:error(transient_fail)
    end.

%% 5. Timeout — handler sleeps past timeout; message is nacked.
timeout_test() ->
    setup_fixture(fixture_timeout, [1, 2]),
    Mod = compile_and_load(
        "pipeline Timeout1\n"
        "  producer :src, source: PipetestProducer, fixture: :fixture_timeout, prefetch: 5\n"
        "  processor :work, concurrency: 1, timeout: 50, retry: 0 do |_n|\n"
        "    Winn_pipeline_tests.forever()\n"
        "  end\n"
        "end\n"),
    process_flag(trap_exit, true),
    {ok, Sup} = Mod:start_link(),
    true = unlink(Sup),
    {ok, _} = wait_nacked(fixture_timeout, 2),
    stop_and_wait(Mod),
    ?assertEqual(0, pipetestproducer:acked(fixture_timeout)),
    [{nacks, N}] = ets:lookup(fixture_timeout, nacks),
    ?assertEqual(2, N),
    ok.

wait_nacked(Fixture, Target) -> wait_nacked(Fixture, Target, 200).
wait_nacked(Fixture, _Target, 0) ->
    [{nacks, V}] = ets:lookup(Fixture, nacks),
    {timeout, V};
wait_nacked(Fixture, Target, N) ->
    case ets:lookup(Fixture, nacks) of
        [{nacks, V}] when V >= Target -> {ok, V};
        _ -> timer:sleep(20), wait_nacked(Fixture, Target, N - 1)
    end.

forever() -> timer:sleep(5000).

%% 6. Batcher size — 7 messages with size:3; expect 3 flushes (3, 3, 1).
batcher_size_test() ->
    setup_fixture(fixture_bsize, lists:seq(1, 7)),
    Mod = compile_and_load(
        "pipeline BSize1\n"
        "  producer :src, source: PipetestProducer, fixture: :fixture_bsize, prefetch: 5\n"
        "  processor :work, concurrency: 1 do |n| n end\n"
        "  batcher :sink, size: 3, timeout: 10000 do |batch|\n"
        "    Winn_pipeline_tests.record_batch(batch)\n"
        "  end\n"
        "end\n"),
    {ok, _} = start_and_wait(Mod, fixture_bsize, 7),
    timer:sleep(100),
    Batches = sink_batches(),
    Sizes = [length(B) || B <- Batches],
    %% Two size-3 batches + a tail (1 item) flushed on terminate.
    ?assert(lists:sum(Sizes) == 7, {batches, Batches}),
    ?assert(lists:member(3, Sizes), {batches, Batches}),
    ok.

%% 7. Batcher timeout — 2 messages, wait for timer to fire.
batcher_timeout_test() ->
    setup_fixture(fixture_btime, [101, 102]),
    Mod = compile_and_load(
        "pipeline BTime1\n"
        "  producer :src, source: PipetestProducer, fixture: :fixture_btime, prefetch: 5\n"
        "  processor :work, concurrency: 1 do |n| n end\n"
        "  batcher :sink, size: 100, timeout: 100 do |batch|\n"
        "    Winn_pipeline_tests.record_batch(batch)\n"
        "  end\n"
        "end\n"),
    process_flag(trap_exit, true),
    {ok, Sup} = Mod:start_link(),
    true = unlink(Sup),
    {ok, _} = pipetestproducer:wait_acked(fixture_btime, 2),
    timer:sleep(300),  %% let the batcher timer fire before stopping
    ?assertMatch([_ | _], sink_batches()),
    Flat = lists:flatten(sink_batches()),
    ?assertEqual([101, 102], lists:sort(Flat)),
    stop_and_wait(Mod),
    ok.

%% 8. Graceful shutdown — pending batch is flushed on terminate.
graceful_shutdown_test() ->
    setup_fixture(fixture_shutdown, [201, 202, 203]),
    Mod = compile_and_load(
        "pipeline Shut1\n"
        "  producer :src, source: PipetestProducer, fixture: :fixture_shutdown, prefetch: 5\n"
        "  processor :work, concurrency: 1 do |n| n end\n"
        "  batcher :sink, size: 100, timeout: 60000 do |batch|\n"
        "    Winn_pipeline_tests.record_batch(batch)\n"
        "  end\n"
        "end\n"),
    process_flag(trap_exit, true),
    {ok, Sup} = Mod:start_link(),
    true = unlink(Sup),
    {ok, _} = pipetestproducer:wait_acked(fixture_shutdown, 3),
    stop_and_wait(Mod),
    %% Batcher terminate should flush remaining 3 items.
    Flat = lists:flatten(sink_batches()),
    ?assertEqual([201, 202, 203], lists:sort(Flat)),
    ok.

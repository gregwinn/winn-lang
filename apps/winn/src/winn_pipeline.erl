%% winn_pipeline.erl
%% Runtime for the `pipeline` keyword — Broadway-shape supervised dataflow.
%%
%% The generated pipeline module is itself a supervisor callback:
%%   Generated start_link/0  -> winn_pipeline:start_link(?MOD, Spec)
%%   Generated stop/0        -> winn_pipeline:stop(?MOD)
%%   Generated stats/0       -> winn_pipeline:stats(?MOD)
%%   Generated init/1        -> winn_pipeline:init(?MOD, Spec, Args)
%%   Generated pipeline_spec/0 returns the map `Spec`.
%%
%% Topology (per pipeline; Name is the compiled module atom):
%%
%%     <Name>_sup (one_for_all, via the generated module as supervisor)
%%     ├── <Name>_batcher       (gen_server, optional)
%%     ├── <Name>_worker_1
%%     ├── ...
%%     ├── <Name>_worker_N
%%     └── <Name>_producer      (gen_server; started LAST, stopped FIRST)
%%
%% Backpressure is prefetch-driven: the producer pulls up to `prefetch`
%% items from the user's source module, distributes them round-robin to
%% the worker pool, and waits for ack messages before pulling more.

-module(winn_pipeline).

%% Public API invoked by generated modules
-export([start_link/2, stop/1, stats/1, init/3]).

%% Producer / worker / batcher callbacks (gen_server)
-export([producer_start_link/3, producer_init/1,
         producer_handle_call/3, producer_handle_cast/2,
         producer_handle_info/2, producer_terminate/2, producer_code_change/3]).

-export([worker_start_link/4, worker_init/1,
         worker_handle_call/3, worker_handle_cast/2,
         worker_handle_info/2, worker_terminate/2, worker_code_change/3]).

-export([batcher_start_link/3, batcher_init/1,
         batcher_handle_call/3, batcher_handle_cast/2,
         batcher_handle_info/2, batcher_terminate/2, batcher_code_change/3]).

-behaviour(gen_server).

%% The behaviour callbacks above are routed through per-role dispatch
%% functions below; gen_server sees them as the standard 6 callbacks
%% based on which start_link launched the process.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(DEFAULT_PREFETCH,     10).
-define(DEFAULT_CONCURRENCY,   1).
-define(DEFAULT_RETRY,         0).
-define(DEFAULT_TIMEOUT,       infinity).
-define(DEFAULT_BATCH_SIZE,  100).
-define(DEFAULT_BATCH_TO,   1000).
-define(SHUTDOWN_TIMEOUT,   5000).

%% ── Public API ────────────────────────────────────────────────────────────

%% Start the pipeline supervisor. Generated module is its own sup callback.
start_link(PipelineMod, _Spec) ->
    supervisor:start_link({local, sup_name(PipelineMod)}, PipelineMod, []).

%% Gracefully stop the pipeline (terminate in reverse order, drain naturally).
stop(PipelineMod) ->
    SupName = sup_name(PipelineMod),
    case whereis(SupName) of
        undefined -> ok;
        Pid -> exit(Pid, shutdown), ok
    end.

%% Snapshot of per-pipeline metrics.
stats(PipelineMod) ->
    Prefix = atom_to_list(PipelineMod),
    Keys = [processed, errors, retries, batch_flushes, in_flight],
    maps:from_list([{K, safe_metric_get(Prefix ++ "." ++ atom_to_list(K))} || K <- Keys]).

safe_metric_get(Key) ->
    try winn_metrics:get(list_to_binary(Key))
    catch _:_ -> 0
    end.

%% Supervisor init callback — builds child specs from the Spec map.
init(PipelineMod, Spec, _Args) ->
    BatcherChildren = case maps:find(batcher, Spec) of
        error -> [];
        {ok, BSpec} -> [batcher_child_spec(PipelineMod, BSpec)]
    end,
    ProcessorSpec = maps:get(processor, Spec),
    Concurrency = maps:get(concurrency, ProcessorSpec, ?DEFAULT_CONCURRENCY),
    BatcherName = case BatcherChildren of [] -> none; _ -> batcher_name(PipelineMod) end,
    WorkerChildren = [worker_child_spec(PipelineMod, N, ProcessorSpec, BatcherName)
                      || N <- lists:seq(1, Concurrency)],
    ProducerSpec = maps:get(producer, Spec),
    WorkerNames = [worker_name(PipelineMod, N) || N <- lists:seq(1, Concurrency)],
    ProducerChild = producer_child_spec(PipelineMod, ProducerSpec, WorkerNames),

    SupFlags = #{strategy => one_for_all, intensity => 3, period => 10},
    Children = BatcherChildren ++ WorkerChildren ++ [ProducerChild],
    {ok, {SupFlags, Children}}.

%% ── Child specs ──────────────────────────────────────────────────────────

batcher_child_spec(PipelineMod, BSpec) ->
    #{id => batcher,
      start => {?MODULE, batcher_start_link, [PipelineMod, BSpec, batcher_name(PipelineMod)]},
      restart => permanent,
      shutdown => ?SHUTDOWN_TIMEOUT,
      type => worker,
      modules => [?MODULE]}.

worker_child_spec(PipelineMod, N, ProcessorSpec, BatcherName) ->
    Name = worker_name(PipelineMod, N),
    #{id => Name,
      start => {?MODULE, worker_start_link, [PipelineMod, N, ProcessorSpec, BatcherName]},
      restart => permanent,
      shutdown => ?SHUTDOWN_TIMEOUT,
      type => worker,
      modules => [?MODULE]}.

producer_child_spec(PipelineMod, ProducerSpec, WorkerNames) ->
    #{id => producer,
      start => {?MODULE, producer_start_link, [PipelineMod, ProducerSpec, WorkerNames]},
      restart => permanent,
      shutdown => ?SHUTDOWN_TIMEOUT,
      type => worker,
      modules => [?MODULE]}.

%% ── Name helpers ─────────────────────────────────────────────────────────

sup_name(PipelineMod) -> PipelineMod.
producer_name(PipelineMod) -> list_to_atom(atom_to_list(PipelineMod) ++ "_producer").
batcher_name(PipelineMod)  -> list_to_atom(atom_to_list(PipelineMod) ++ "_batcher").
worker_name(PipelineMod, N) ->
    list_to_atom(atom_to_list(PipelineMod) ++ "_worker_" ++ integer_to_list(N)).

metric_key(PipelineMod, Suffix) ->
    list_to_binary(atom_to_list(PipelineMod) ++ "." ++ Suffix).

%% ── Generic gen_server shim ──────────────────────────────────────────────
%% Each process identifies its role by the first element of its state tuple.

init({producer, PipelineMod, ProducerSpec, WorkerNames}) ->
    producer_init({PipelineMod, ProducerSpec, WorkerNames});
init({worker, PipelineMod, N, ProcessorSpec, BatcherName}) ->
    worker_init({PipelineMod, N, ProcessorSpec, BatcherName});
init({batcher, PipelineMod, BSpec}) ->
    batcher_init({PipelineMod, BSpec}).

handle_call(Req, From, S = #{role := producer}) -> producer_handle_call(Req, From, S);
handle_call(Req, From, S = #{role := worker})   -> worker_handle_call(Req, From, S);
handle_call(Req, From, S = #{role := batcher})  -> batcher_handle_call(Req, From, S).

handle_cast(Msg, S = #{role := producer}) -> producer_handle_cast(Msg, S);
handle_cast(Msg, S = #{role := worker})   -> worker_handle_cast(Msg, S);
handle_cast(Msg, S = #{role := batcher})  -> batcher_handle_cast(Msg, S).

handle_info(Msg, S = #{role := producer}) -> producer_handle_info(Msg, S);
handle_info(Msg, S = #{role := worker})   -> worker_handle_info(Msg, S);
handle_info(Msg, S = #{role := batcher})  -> batcher_handle_info(Msg, S).

terminate(R, S = #{role := producer}) -> producer_terminate(R, S);
terminate(R, S = #{role := worker})   -> worker_terminate(R, S);
terminate(R, S = #{role := batcher})  -> batcher_terminate(R, S).

code_change(V, S = #{role := producer}, E) -> producer_code_change(V, S, E);
code_change(V, S = #{role := worker},   E) -> worker_code_change(V, S, E);
code_change(V, S = #{role := batcher},  E) -> batcher_code_change(V, S, E).

%% ── Producer ─────────────────────────────────────────────────────────────

producer_start_link(PipelineMod, ProducerSpec, WorkerNames) ->
    gen_server:start_link({local, producer_name(PipelineMod)},
                          ?MODULE,
                          {producer, PipelineMod, ProducerSpec, WorkerNames},
                          []).

producer_init({PipelineMod, ProducerSpec, WorkerNames}) ->
    process_flag(trap_exit, true),
    Source    = maps:get(source, ProducerSpec),
    Prefetch  = maps:get(prefetch, ProducerSpec, ?DEFAULT_PREFETCH),
    UserOpts  = extract_user_opts(ProducerSpec),
    UserMod   = resolve_user_mod(Source),
    case safe_apply(UserMod, init, [UserOpts]) of
        {ok, UserState} ->
            State = #{role => producer,
                      pipeline => PipelineMod,
                      user_mod => UserMod,
                      user_state => UserState,
                      prefetch => Prefetch,
                      workers => list_to_tuple(WorkerNames),
                      cursor => 0,
                      in_flight => 0,
                      draining => false},
            self() ! pull,
            {ok, State};
        {error, Reason} ->
            {stop, {producer_init_failed, Reason}};
        Other ->
            {stop, {producer_init_bad_return, Other}}
    end.

%% Trim framework-only keys before calling user producer:init/1.
extract_user_opts(ProducerSpec) ->
    Framework = [name, source, prefetch],
    maps:without(Framework, ProducerSpec).

resolve_user_mod(Atom) when is_atom(Atom) ->
    %% Winn PascalCase module names compile to lowercase atoms;
    %% runtime may receive either. Try lowercased form first, fall back.
    Lower = list_to_atom(string:lowercase(atom_to_list(Atom))),
    case code:ensure_loaded(Lower) of
        {module, Lower} -> Lower;
        _ -> Atom
    end.

producer_handle_call(_Req, _From, State) ->
    {reply, {error, unsupported}, State}.

producer_handle_cast(_Msg, State) ->
    {noreply, State}.

producer_handle_info(pull, State = #{draining := true}) ->
    {noreply, State};
producer_handle_info(pull, State) ->
    #{user_mod := UserMod, user_state := UState,
      prefetch := Prefetch, in_flight := InFlight,
      workers := Workers, cursor := Cursor,
      pipeline := Pipeline} = State,
    Demand = max(0, Prefetch - InFlight),
    case Demand of
        0 -> {noreply, State};
        _ ->
            case safe_apply(UserMod, pull, [UState, Demand]) of
                {ok, [], NewUState} ->
                    %% No messages available; retry after a short pause.
                    erlang:send_after(100, self(), pull),
                    {noreply, State#{user_state := NewUState}};
                {ok, Messages, NewUState} ->
                    {NewCursor, _} = dispatch(Messages, Workers, Cursor, Pipeline),
                    NewInFlight = InFlight + length(Messages),
                    update_gauge(Pipeline, "in_flight", NewInFlight),
                    {noreply, State#{user_state := NewUState,
                                     cursor := NewCursor,
                                     in_flight := NewInFlight}};
                {error, Reason, NewUState} ->
                    winn_logger:error(<<"pipeline producer pull failed">>,
                                      #{pipeline => Pipeline, reason => format_reason(Reason)}),
                    erlang:send_after(500, self(), pull),
                    {noreply, State#{user_state := NewUState}}
            end
    end;
producer_handle_info({ack, Message, Outcome}, State) ->
    #{user_mod := UserMod, user_state := UState,
      in_flight := InFlight, pipeline := Pipeline} = State,
    NewUState = try
        safe_apply(UserMod, ack, [UState, Message, Outcome])
    catch
        Class:Err ->
            winn_logger:error(<<"pipeline producer ack raised">>,
                              #{pipeline => Pipeline, class => Class,
                                reason => format_reason(Err)}),
            UState
    end,
    NewInFlight = max(0, InFlight - 1),
    update_gauge(Pipeline, "in_flight", NewInFlight),
    self() ! pull,
    {noreply, State#{user_state := NewUState, in_flight := NewInFlight}};
producer_handle_info(_, State) ->
    {noreply, State}.

producer_terminate(Reason, State = #{user_mod := UserMod, user_state := UState,
                                     pipeline := Pipeline}) ->
    %% Mark draining so subsequent pulls are no-ops if we get rescheduled.
    drain_until_idle(State, 0),
    try safe_apply(UserMod, terminate, [UState, Reason])
    catch _:_ -> ok end,
    winn_logger:info(<<"pipeline producer terminated">>,
                     #{pipeline => Pipeline, reason => format_reason(Reason)}),
    ok;
producer_terminate(_Reason, _) -> ok.

producer_code_change(_, State, _) -> {ok, State}.

%% Dispatch messages round-robin across workers.
%% Returns {NewCursor, SentCount}.
dispatch([], _Workers, Cursor, _Pipeline) ->
    {Cursor, 0};
dispatch(Messages, Workers, Cursor, Pipeline) ->
    dispatch_loop(Messages, Workers, Cursor, 0, Pipeline).

dispatch_loop([], _Workers, Cursor, Count, _) ->
    {Cursor, Count};
dispatch_loop([Msg | Rest], Workers, Cursor, Count, Pipeline) ->
    N = tuple_size(Workers),
    WorkerName = element((Cursor rem N) + 1, Workers),
    ProducerPid = self(),
    gen_server:cast(WorkerName, {process, Msg, ProducerPid}),
    dispatch_loop(Rest, Workers, Cursor + 1, Count + 1, Pipeline).

drain_until_idle(#{in_flight := 0}, _) -> ok;
drain_until_idle(_, Elapsed) when Elapsed >= ?SHUTDOWN_TIMEOUT -> ok;
drain_until_idle(State, Elapsed) ->
    receive
        {ack, _, _} = Msg ->
            {noreply, NewState} = producer_handle_info(Msg, State#{draining := true}),
            drain_until_idle(NewState, Elapsed + 10)
    after 100 ->
        drain_until_idle(State, Elapsed + 100)
    end.

%% ── Worker ───────────────────────────────────────────────────────────────

worker_start_link(PipelineMod, N, ProcessorSpec, BatcherName) ->
    gen_server:start_link({local, worker_name(PipelineMod, N)},
                          ?MODULE,
                          {worker, PipelineMod, N, ProcessorSpec, BatcherName},
                          []).

worker_init({PipelineMod, N, ProcessorSpec, BatcherName}) ->
    process_flag(trap_exit, true),
    State = #{role => worker,
              pipeline => PipelineMod,
              index => N,
              mod => maps:get(module, ProcessorSpec),
              handler => maps:get(handler, ProcessorSpec),
              retry => maps:get(retry, ProcessorSpec, ?DEFAULT_RETRY),
              timeout => maps:get(timeout, ProcessorSpec, ?DEFAULT_TIMEOUT),
              batcher => BatcherName},
    {ok, State}.

worker_handle_call(_Req, _From, State) ->
    {reply, {error, unsupported}, State}.

worker_handle_cast({process, Message, ProducerPid}, State) ->
    #{mod := Mod, handler := H, retry := Retry, timeout := Timeout,
      batcher := Batcher, pipeline := Pipeline} = State,
    case run_handler(Mod, H, Message, Retry, Timeout, Pipeline) of
        {ok, Result} ->
            case Batcher of
                none -> ok;
                _    -> gen_server:cast(Batcher, {batch, Result})
            end,
            winn_metrics_incr(Pipeline, "processed"),
            ProducerPid ! {ack, Message, ack},
            {noreply, State};
        {error, Reason} ->
            winn_metrics_incr(Pipeline, "errors"),
            winn_logger:error(<<"pipeline processor failed">>,
                              #{pipeline => Pipeline,
                                reason => format_reason(Reason)}),
            ProducerPid ! {ack, Message, {nack, Reason}},
            {noreply, State}
    end;
worker_handle_cast(_Msg, State) ->
    {noreply, State}.

worker_handle_info(_Msg, State) -> {noreply, State}.

worker_terminate(_Reason, _State) -> ok.

worker_code_change(_, State, _) -> {ok, State}.

%% Handler invocation with retry + optional timeout.
run_handler(Mod, H, Message, Retry, Timeout, Pipeline) ->
    Invoke = fun() ->
        case Timeout of
            infinity -> erlang:apply(Mod, H, [Message]);
            Ms when is_integer(Ms) ->
                Parent = self(),
                Ref = make_ref(),
                Pid = spawn(fun() ->
                    R = try {ok, erlang:apply(Mod, H, [Message])}
                        catch C:E:S -> {exception, C, E, S} end,
                    Parent ! {Ref, R}
                end),
                receive
                    {Ref, {ok, V}} -> V;
                    {Ref, {exception, C, E, _}} -> erlang:C(E)
                after Ms ->
                    exit(Pid, kill),
                    erlang:error({pipeline_handler_timeout, Ms})
                end
        end
    end,
    attempt(Invoke, Retry + 1, Pipeline, undefined).

attempt(_F, 0, _Pipeline, LastErr) -> {error, LastErr};
attempt(F, N, Pipeline, _LastErr) ->
    try {ok, F()}
    catch
        Class:Reason:_Stack ->
            case N of
                1 -> {error, {Class, Reason}};
                _ ->
                    winn_metrics_incr(Pipeline, "retries"),
                    attempt(F, N - 1, Pipeline, {Class, Reason})
            end
    end.

%% ── Batcher ──────────────────────────────────────────────────────────────

batcher_start_link(PipelineMod, BSpec, Name) ->
    gen_server:start_link({local, Name},
                          ?MODULE,
                          {batcher, PipelineMod, BSpec},
                          []).

batcher_init({PipelineMod, BSpec}) ->
    process_flag(trap_exit, true),
    Size    = maps:get(size, BSpec, ?DEFAULT_BATCH_SIZE),
    Timeout = maps:get(timeout, BSpec, ?DEFAULT_BATCH_TO),
    State = #{role => batcher,
              pipeline => PipelineMod,
              mod => maps:get(module, BSpec),
              handler => maps:get(handler, BSpec),
              size => Size,
              timeout => Timeout,
              buffer => [],
              timer => undefined},
    {ok, State}.

batcher_handle_call(_Req, _From, State) ->
    {reply, {error, unsupported}, State}.

batcher_handle_cast({batch, Item}, State) ->
    #{buffer := Buf, size := Size} = State,
    Buf1 = [Item | Buf],
    State1 = State#{buffer := Buf1},
    case length(Buf1) >= Size of
        true  -> {noreply, flush(State1)};
        false -> {noreply, arm_timer(State1)}
    end;
batcher_handle_cast(_Msg, State) ->
    {noreply, State}.

batcher_handle_info(flush_timer, State) ->
    {noreply, flush(State#{timer := undefined})};
batcher_handle_info(_Msg, State) -> {noreply, State}.

batcher_terminate(_Reason, State) ->
    %% Drain any casts already in the mailbox before flushing so items
    %% in flight at shutdown aren't lost.
    State1 = drain_pending_batches(State),
    _ = flush(State1),
    ok.

drain_pending_batches(State = #{buffer := Buf}) ->
    receive
        {'$gen_cast', {batch, Item}} ->
            drain_pending_batches(State#{buffer := [Item | Buf]})
    after 0 ->
        State
    end.

batcher_code_change(_, State, _) -> {ok, State}.

arm_timer(State = #{timer := undefined, timeout := T}) ->
    Ref = erlang:send_after(T, self(), flush_timer),
    State#{timer := Ref};
arm_timer(State) -> State.

flush(State = #{buffer := []}) ->
    State;
flush(State = #{buffer := Buf, mod := Mod, handler := H,
                pipeline := Pipeline, timer := Timer}) ->
    case Timer of
        undefined -> ok;
        _ -> erlang:cancel_timer(Timer)
    end,
    Batch = lists:reverse(Buf),
    try
        _ = erlang:apply(Mod, H, [Batch]),
        winn_metrics_incr(Pipeline, "batch_flushes")
    catch
        Class:Reason ->
            winn_logger:error(<<"pipeline batcher flush failed">>,
                              #{pipeline => Pipeline, class => Class,
                                reason => format_reason(Reason)})
    end,
    State#{buffer := [], timer := undefined}.

%% ── Metrics helpers ──────────────────────────────────────────────────────

winn_metrics_incr(Pipeline, Suffix) ->
    try winn_metrics:increment(metric_key(Pipeline, Suffix))
    catch _:_ -> ok end.

update_gauge(Pipeline, Suffix, Value) ->
    try winn_metrics:set(metric_key(Pipeline, Suffix), Value)
    catch _:_ -> ok end.

%% ── Misc helpers ─────────────────────────────────────────────────────────

safe_apply(Mod, Fun, Args) ->
    erlang:apply(Mod, Fun, Args).

format_reason(R) ->
    try iolist_to_binary(io_lib:format("~p", [R]))
    catch _:_ -> <<"unknown">> end.

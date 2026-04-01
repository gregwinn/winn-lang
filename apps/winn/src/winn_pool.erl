%% winn_pool.erl
%% Simple connection pool for database connections.
%% GenServer that maintains a pool of idle connections and checks them out/in.

-module(winn_pool).
-behaviour(gen_server).

-export([start/1, checkout/0, checkin/1, stop/0, status/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SERVER, ?MODULE).
-define(DEFAULT_POOL_SIZE, 5).
-define(CHECKOUT_TIMEOUT, 5000).

%% ── Public API ───────────────────────────────────────────────────────────────

-spec start(map()) -> {ok, pid()} | {error, term()}.
start(Config) ->
    gen_server:start({local, ?SERVER}, ?MODULE, Config, []).

-spec checkout() -> {ok, pid()} | {error, term()}.
checkout() ->
    gen_server:call(?SERVER, checkout, ?CHECKOUT_TIMEOUT).

-spec checkin(pid()) -> ok.
checkin(Conn) ->
    gen_server:cast(?SERVER, {checkin, Conn}).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?SERVER).

-spec status() -> map().
status() ->
    gen_server:call(?SERVER, status).

%% ── GenServer callbacks ──────────────────────────────────────────────────────

init(Config) ->
    PoolSize = maps:get(pool_size, Config, ?DEFAULT_POOL_SIZE),
    ConnConfig = maps:without([pool_size], Config),
    %% Create initial connections
    {Conns, Errors} = create_connections(ConnConfig, PoolSize),
    case Errors of
        [] -> ok;
        _  -> io:format("Warning: ~B pool connection(s) failed to initialize~n", [length(Errors)])
    end,
    {ok, #{
        idle => Conns,
        busy => [],
        config => ConnConfig,
        pool_size => PoolSize
    }}.

handle_call(checkout, _From, #{idle := [Conn | Rest], busy := Busy} = State) ->
    %% Connection available — check it out
    case is_alive(Conn) of
        true ->
            {reply, {ok, Conn}, State#{idle => Rest, busy => [Conn | Busy]}};
        false ->
            %% Dead connection — try to create a new one
            case create_one(maps:get(config, State)) of
                {ok, NewConn} ->
                    {reply, {ok, NewConn}, State#{idle => Rest, busy => [NewConn | Busy]}};
                {error, Reason} ->
                    {reply, {error, Reason}, State#{idle => Rest}}
            end
    end;
handle_call(checkout, _From, #{idle := [], config := Config, busy := Busy, pool_size := Max} = State) ->
    %% No idle connections — try to create one if under max
    case length(Busy) < Max of
        true ->
            case create_one(Config) of
                {ok, Conn} ->
                    {reply, {ok, Conn}, State#{busy => [Conn | Busy]}};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        false ->
            {reply, {error, pool_exhausted}, State}
    end;

handle_call(status, _From, #{idle := Idle, busy := Busy, pool_size := Max} = State) ->
    {reply, #{idle => length(Idle), busy => length(Busy), max => Max}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast({checkin, Conn}, #{idle := Idle, busy := Busy} = State) ->
    NewBusy = lists:delete(Conn, Busy),
    case is_alive(Conn) of
        true  -> {noreply, State#{idle => [Conn | Idle], busy => NewBusy}};
        false -> {noreply, State#{busy => NewBusy}}
    end;
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Conn, _Reason}, #{idle := Idle, busy := Busy} = State) ->
    {noreply, State#{
        idle => lists:delete(Conn, Idle),
        busy => lists:delete(Conn, Busy)
    }};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #{idle := Idle, busy := Busy}) ->
    lists:foreach(fun close_conn/1, Idle ++ Busy),
    ok.

%% ── Internal ─────────────────────────────────────────────────────────────────

create_connections(Config, N) ->
    Results = [create_one(Config) || _ <- lists:seq(1, N)],
    Conns  = [C || {ok, C} <- Results],
    Errors = [E || {error, E} <- Results],
    {Conns, Errors}.

create_one(Config) ->
    #{host := Host, port := Port, database := DB,
      username := User, password := Pass} = Config,
    epgsql:connect(#{host => Host, port => Port, database => DB,
                     username => User, password => Pass}).

is_alive(Conn) when is_pid(Conn) ->
    erlang:is_process_alive(Conn);
is_alive(_) ->
    false.

close_conn(Conn) ->
    try epgsql:close(Conn) catch _:_ -> ok end.

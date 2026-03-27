%% winn_ws.erl
%% M6 — WebSocket client for Winn programs.
%%
%% WS.connect(url)      -> {:ok, conn} | {:error, reason}
%% WS.send(conn, data)  -> ok | {:error, reason}
%% WS.recv(conn)        -> {:ok, msg} | {:error, reason}
%% WS.recv(conn, timeout_ms) -> {:ok, msg} | {:error, timeout}
%% WS.close(conn)       -> ok
%%
%% conn is a map #{pid => GunPid, stream => StreamRef, protocol => ws}

-module(winn_ws).
-export([connect/1, send/2, recv/1, recv/2, close/1]).

%% Connect to a WebSocket URL.
%% Supports ws:// and wss:// schemes.
connect(Url) when is_binary(Url) ->
    ensure_started(),
    {Scheme, Host, Port, Path} = parse_ws_url(Url),
    TransportOpts = case Scheme of
        wss -> #{transport => tls, tls_opts => [{verify, verify_none}]};
        ws  -> #{}
    end,
    case gun:open(binary_to_list(Host), Port, TransportOpts) of
        {ok, Pid} ->
            case gun:await_up(Pid, 5000) of
                {ok, _Protocol} ->
                    StreamRef = gun:ws_upgrade(Pid, binary_to_list(Path)),
                    case wait_for_upgrade(Pid, StreamRef) of
                        ok ->
                            Conn = #{pid => Pid, stream => StreamRef, protocol => ws},
                            {ok, Conn};
                        {error, Reason} ->
                            gun:close(Pid),
                            {error, Reason}
                    end;
                {error, Reason} ->
                    gun:close(Pid),
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Send data over the WebSocket.
%% Maps are JSON-encoded, binaries sent as text frames.
send(#{pid := Pid, stream := _StreamRef}, Data) when is_map(Data) ->
    Json = jsone:encode(Data),
    gun:ws_send(Pid, {text, Json}),
    ok;
send(#{pid := Pid, stream := _StreamRef}, Data) when is_binary(Data) ->
    gun:ws_send(Pid, {text, Data}),
    ok.

%% Receive with default 5 second timeout.
recv(Conn) ->
    recv(Conn, 5000).

%% Receive a WebSocket message with timeout.
recv(#{pid := Pid}, Timeout) ->
    receive
        {gun_ws, Pid, _StreamRef, {text, Msg}} ->
            {ok, Msg};
        {gun_ws, Pid, _StreamRef, {binary, Msg}} ->
            {ok, Msg};
        {gun_ws, Pid, _StreamRef, close} ->
            {error, closed};
        {gun_ws, Pid, _StreamRef, {close, _Code, _Reason}} ->
            {error, closed}
    after Timeout ->
        {error, timeout}
    end.

%% Close the WebSocket connection.
close(#{pid := Pid}) ->
    gun:close(Pid),
    ok.

%% ── Internal helpers ────────────────────────────────────────────────────

ensure_started() ->
    _ = application:ensure_all_started(gun),
    ok.

parse_ws_url(Url) ->
    {Scheme, Rest} = case Url of
        <<"wss://", R/binary>> -> {wss, R};
        <<"ws://", R/binary>>  -> {ws, R};
        _ -> {ws, Url}
    end,
    DefaultPort = case Scheme of wss -> 443; ws -> 80 end,
    {HostPort, Path} = case binary:split(Rest, <<"/">>) of
        [HP]      -> {HP, <<"/">>};
        [HP, Pth] -> {HP, <<"/", Pth/binary>>}
    end,
    {Host, Port} = case binary:split(HostPort, <<":">>) of
        [H]      -> {H, DefaultPort};
        [H, Pt]  -> {H, binary_to_integer(Pt)}
    end,
    {Scheme, Host, Port, Path}.

wait_for_upgrade(Pid, StreamRef) ->
    receive
        {gun_upgrade, Pid, StreamRef, [<<"websocket">>], _Headers} ->
            ok;
        {gun_response, Pid, StreamRef, _, Status, _Headers} ->
            {error, {upgrade_failed, Status}};
        {gun_error, Pid, StreamRef, Reason} ->
            {error, Reason}
    after 5000 ->
        {error, upgrade_timeout}
    end.

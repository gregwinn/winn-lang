%% winn_mailer.erl
%% Pluggable email delivery for Winn programs (the `Mailer` module).
%%
%%   Mailer.send(to, subject, body)        -> {ok, transport} | {error, reason}
%%   Mailer.send(to, subject, body, opts)  -> {ok, transport} | {error, reason}
%%     opts keys: from, reply_to (strings), html (boolean — text/html vs text/plain)
%%
%% The transport is chosen from config (`Config.put(:mailer, :transport, ...)`):
%%   :test  — capture messages in-process (assert with winn_mailer:captured/0)
%%   :http  — POST to SendGrid's v3 API (set :api_key and :from in config)
%%
%% SMTP is intentionally not implemented yet — it would pull in a new dependency
%% (e.g. gen_smtp); deferred until there's demand. Use the :http provider or a
%% provider's HTTP API for now.
-module(winn_mailer).
-export([send/3, send/4]).
-export([captured/0, clear/0]).      %% test transport helpers
-export([sendgrid_payload/1]).       %% exported for tests

-define(CAPTURE_TAB, winn_mailer_captured).
-define(SENDGRID_URL, <<"https://api.sendgrid.com/v3/mail/send">>).

%% ── API ──────────────────────────────────────────────────────────────────────

send(To, Subject, Body) ->
    send(To, Subject, Body, #{}).

send(To, Subject, Body, Opts)
        when is_binary(To), is_binary(Subject), is_binary(Body), is_map(Opts) ->
    Msg = #{to       => To,
            subject  => Subject,
            body     => Body,
            from     => maps:get(from, Opts, default_from()),
            html     => maps:get(html, Opts, false),
            reply_to => maps:get(reply_to, Opts, nil)},
    dispatch(transport(), Msg).

%% ── Transports ───────────────────────────────────────────────────────────────

dispatch(test, Msg)   -> capture(Msg), {ok, test};
dispatch(http, Msg)   -> send_sendgrid(Msg);
dispatch(nil, _Msg)   -> {error, no_transport};
dispatch(Other, _Msg) -> {error, {unknown_transport, Other}}.

%% SendGrid v3 — needs a custom Authorization header, so call hackney directly
%% (winn_http doesn't expose request headers).
send_sendgrid(Msg) ->
    case winn_config:get(mailer, api_key) of
        nil ->
            {error, no_api_key};
        ApiKey ->
            Url     = endpoint(),
            Headers = [{<<"authorization">>, <<"Bearer ", ApiKey/binary>>},
                       {<<"content-type">>, <<"application/json">>}],
            Payload = sendgrid_payload(Msg),
            case hackney:request(post, Url, Headers, Payload, [{follow_redirect, true}]) of
                {ok, Status, _H, Ref} when Status >= 200, Status < 300 ->
                    _ = hackney:body(Ref),
                    {ok, sent};
                {ok, Status, _H, Ref} ->
                    {ok, RespBody} = hackney:body(Ref),
                    {error, {http_error, Status, RespBody}};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

sendgrid_payload(#{to := To, from := From, subject := Subject,
                   body := Body} = Msg) ->
    ContentType = case maps:get(html, Msg, false) of
                      true -> <<"text/html">>;
                      _    -> <<"text/plain">>
                  end,
    Base = #{personalizations => [#{to => [#{email => To}]}],
             from             => #{email => From},
             subject          => Subject,
             content          => [#{type => ContentType, value => Body}]},
    Full = case maps:get(reply_to, Msg, nil) of
               R when is_binary(R) -> Base#{reply_to => #{email => R}};
               _                   -> Base
           end,
    jsone:encode(Full).

%% ── Test transport (capture) ─────────────────────────────────────────────────

%% Sent messages, in order. For tests asserting on delivered mail.
captured() ->
    ensure_tab(),
    [Msg || {_, Msg} <- lists:sort(ets:tab2list(?CAPTURE_TAB))].

clear() ->
    ensure_tab(),
    ets:delete_all_objects(?CAPTURE_TAB),
    ok.

capture(Msg) ->
    ensure_tab(),
    N = ets:info(?CAPTURE_TAB, size) + 1,
    ets:insert(?CAPTURE_TAB, {N, Msg}),
    ok.

ensure_tab() ->
    case ets:whereis(?CAPTURE_TAB) of
        undefined -> ets:new(?CAPTURE_TAB, [named_table, public, ordered_set]);
        _         -> ?CAPTURE_TAB
    end.

%% ── Config ───────────────────────────────────────────────────────────────────

transport() -> winn_config:get(mailer, transport).

default_from() ->
    case winn_config:get(mailer, from) of
        nil -> <<"no-reply@example.com">>;
        F   -> F
    end.

endpoint() ->
    case winn_config:get(mailer, endpoint) of
        nil -> ?SENDGRID_URL;
        E   -> E
    end.

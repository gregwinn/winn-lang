%% winn_mailer_tests — Mailer (#166). Uses the in-process `test` transport to
%% assert on delivered mail without sending anything.
-module(winn_mailer_tests).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    winn_config:put(mailer, transport, test),
    winn_config:put(mailer, from, <<"app@example.com">>),
    winn_mailer:clear().

send_captures_message_test() ->
    setup(),
    ?assertEqual({ok, test}, winn_mailer:send(<<"a@b.com">>, <<"Hi">>, <<"Body">>)),
    [Msg] = winn_mailer:captured(),
    ?assertEqual(<<"a@b.com">>, maps:get(to, Msg)),
    ?assertEqual(<<"Hi">>, maps:get(subject, Msg)),
    ?assertEqual(<<"Body">>, maps:get(body, Msg)),
    ?assertEqual(<<"app@example.com">>, maps:get(from, Msg)).

send_with_opts_test() ->
    setup(),
    {ok, test} = winn_mailer:send(<<"a@b.com">>, <<"S">>, <<"<b>Hi</b>">>,
        #{from => <<"custom@example.com">>, html => true}),
    [Msg] = winn_mailer:captured(),
    ?assertEqual(<<"custom@example.com">>, maps:get(from, Msg)),
    ?assert(maps:get(html, Msg)).

multiple_sends_accumulate_in_order_test() ->
    setup(),
    winn_mailer:send(<<"a@b.com">>, <<"1">>, <<"x">>),
    winn_mailer:send(<<"c@d.com">>, <<"2">>, <<"y">>),
    Captured = winn_mailer:captured(),
    ?assertEqual(2, length(Captured)),
    ?assertEqual([<<"1">>, <<"2">>], [maps:get(subject, M) || M <- Captured]).

clear_empties_the_box_test() ->
    setup(),
    winn_mailer:send(<<"a@b.com">>, <<"S">>, <<"B">>),
    winn_mailer:clear(),
    ?assertEqual([], winn_mailer:captured()).

unknown_transport_test() ->
    setup(),
    winn_config:put(mailer, transport, nil),
    ?assertEqual({error, no_transport}, winn_mailer:send(<<"a@b">>, <<"s">>, <<"b">>)),
    winn_config:put(mailer, transport, carrier_pigeon),
    ?assertMatch({error, {unknown_transport, carrier_pigeon}},
                 winn_mailer:send(<<"a@b">>, <<"s">>, <<"b">>)).

http_without_api_key_test() ->
    setup(),
    winn_config:put(mailer, transport, http),
    winn_config:put(mailer, api_key, nil),
    ?assertEqual({error, no_api_key}, winn_mailer:send(<<"a@b">>, <<"s">>, <<"b">>)).

sendgrid_payload_shape_test() ->
    Json = winn_mailer:sendgrid_payload(#{to => <<"a@b.com">>, from => <<"f@x.com">>,
        subject => <<"S">>, body => <<"B">>, html => false, reply_to => nil}),
    D = jsone:decode(Json, [{object_format, map}]),
    ?assertEqual(<<"S">>, maps:get(<<"subject">>, D)),
    ?assertEqual(<<"f@x.com">>, maps:get(<<"email">>, maps:get(<<"from">>, D))),
    [P] = maps:get(<<"personalizations">>, D),
    [T] = maps:get(<<"to">>, P),
    ?assertEqual(<<"a@b.com">>, maps:get(<<"email">>, T)),
    [C] = maps:get(<<"content">>, D),
    ?assertEqual(<<"text/plain">>, maps:get(<<"type">>, C)),
    ?assertEqual(<<"B">>, maps:get(<<"value">>, C)).

sendgrid_payload_html_test() ->
    Json = winn_mailer:sendgrid_payload(#{to => <<"a@b.com">>, from => <<"f@x.com">>,
        subject => <<"S">>, body => <<"<b>B</b>">>, html => true, reply_to => nil}),
    D = jsone:decode(Json, [{object_format, map}]),
    [C] = maps:get(<<"content">>, D),
    ?assertEqual(<<"text/html">>, maps:get(<<"type">>, C)).

%% End-to-end through the compiler: `Mailer.send` must resolve and run.
e2e_mailer_send_test() ->
    setup(),
    Src = "module MailFlow\n"
          "  def run()\n"
          "    Mailer.send(\"e2e@example.com\", \"Hello\", \"Body\")\n"
          "  end\n"
          "end\n",
    Mod = compile_and_load(Src),
    ?assertEqual({ok, test}, Mod:run()),
    [Msg] = winn_mailer:captured(),
    ?assertEqual(<<"e2e@example.com">>, maps:get(to, Msg)).

compile_and_load(Source) ->
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST} = winn_parser:parse(Tokens),
    Transformed = winn_transform:transform(AST),
    [CoreMod] = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

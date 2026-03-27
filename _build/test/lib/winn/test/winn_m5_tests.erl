%% winn_m5_tests.erl — M5: JWT tests.

-module(winn_m5_tests).
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

%% ── Direct tests ────────────────────────────────────────────────────────

sign_returns_binary_test() ->
    Token = winn_jwt:sign(#{user_id => 42}, <<"secret">>),
    ?assert(is_binary(Token)),
    %% JWT has 3 parts separated by dots.
    Parts = binary:split(Token, <<".">>, [global]),
    ?assertEqual(3, length(Parts)).

sign_verify_roundtrip_test() ->
    Claims = #{user_id => 42, role => <<"admin">>},
    Secret = <<"my_secret_key">>,
    Token = winn_jwt:sign(Claims, Secret),
    {ok, Decoded} = winn_jwt:verify(Token, Secret),
    ?assertEqual(42, maps:get(<<"user_id">>, Decoded)),
    ?assertEqual(<<"admin">>, maps:get(<<"role">>, Decoded)).

verify_wrong_secret_test() ->
    Token = winn_jwt:sign(#{foo => <<"bar">>}, <<"secret1">>),
    ?assertEqual({error, invalid_signature}, winn_jwt:verify(Token, <<"secret2">>)).

verify_tampered_token_test() ->
    Token = winn_jwt:sign(#{foo => <<"bar">>}, <<"secret">>),
    %% Tamper with the payload
    [H, _P, S] = binary:split(Token, <<".">>, [global]),
    Tampered = <<H/binary, ".", "eyJmb28iOiJoYWNrZWQifQ", ".", S/binary>>,
    ?assertEqual({error, invalid_signature}, winn_jwt:verify(Tampered, <<"secret">>)).

verify_expired_token_test() ->
    %% Create a token that expired in the past.
    Claims = #{user_id => 1, exp => os:system_time(second) - 3600},
    Token = winn_jwt:sign(Claims, <<"secret">>),
    ?assertEqual({error, expired}, winn_jwt:verify(Token, <<"secret">>)).

verify_not_expired_test() ->
    %% Create a token that expires in the future.
    Claims = #{user_id => 1, exp => os:system_time(second) + 3600},
    Token = winn_jwt:sign(Claims, <<"secret">>),
    ?assertMatch({ok, _}, winn_jwt:verify(Token, <<"secret">>)).

verify_malformed_test() ->
    ?assertEqual({error, malformed_token}, winn_jwt:verify(<<"not.a.jwt.token">>, <<"s">>)),
    ?assertEqual({error, malformed_token}, winn_jwt:verify(<<"garbage">>, <<"s">>)).

%% ── E2E tests ───────────────────────────────────────────────────────────

e2e_sign_test() ->
    Src = "module JwtTest\n  def run()\n    JWT.sign(%{user_id: 42}, \"secret\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    Token = Mod:run(),
    ?assert(is_binary(Token)),
    ?assertEqual(3, length(binary:split(Token, <<".">>, [global]))).

e2e_verify_test() ->
    Src = "module JwtVer\n  def run(token)\n    JWT.verify(token, \"secret\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    Token = winn_jwt:sign(#{user_id => 99}, <<"secret">>),
    {ok, Claims} = Mod:run(Token),
    ?assertEqual(99, maps:get(<<"user_id">>, Claims)).

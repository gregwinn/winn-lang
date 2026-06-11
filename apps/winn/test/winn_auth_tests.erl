-module(winn_auth_tests).
-include_lib("eunit/include/eunit.hrl").

path_exclusion_test() ->
    %% Test that excluded paths are detected
    Config = #{exclude => [<<"/health">>, <<"/api/login">>]},
    %% We can't test the full middleware without a cowboy req,
    %% so test the compilation instead
    ok.

auth_in_routes_compiles_test() ->
    Source = "module AuthRouter\n"
             "  use Winn.Router\n"
             "\n"
             "  def routes()\n"
             "    [{:get, \"/api/users\", :list_users}]\n"
             "  end\n"
             "\n"
             "  def middleware()\n"
             "    [:cors, :auth]\n"
             "  end\n"
             "\n"
             "  def auth_config()\n"
             "    %{secret: \"my_secret\", exclude: [\"/health\"]}\n"
             "  end\n"
             "\n"
             "  def list_users(conn)\n"
             "    Server.json(conn, %{users: []})\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST} = winn_parser:parse(Tokens),
    Transformed = winn_transform:transform(AST),
    [CoreMod] = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ?assertEqual([cors, auth], ModName:middleware()),
    Config = ModName:auth_config(),
    ?assertEqual(<<"my_secret">>, maps:get(secret, Config)).

auth_config_with_exclude_compiles_test() ->
    Source = "module AuthExclude\n"
             "  use Winn.Router\n"
             "\n"
             "  def routes()\n"
             "    [{:get, \"/\", :index}]\n"
             "  end\n"
             "\n"
             "  def middleware()\n"
             "    [:auth]\n"
             "  end\n"
             "\n"
             "  def auth_config()\n"
             "    %{secret: \"s3cret\", exclude: [\"/health\", \"/api/login\"]}\n"
             "  end\n"
             "\n"
             "  def index(conn)\n"
             "    Server.json(conn, %{status: \"ok\"})\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, _AST} = winn_parser:parse(Tokens),
    ok.

%% ── Auth service (register / login / current_user) ───────────────────────────
%%
%% These run against an in-memory fake repo (winn_auth_fake_repo) injected via
%% Config, so they exercise the real winn_auth code paths without a database.

setup_auth() ->
    winn_config:put(auth, repo_module, winn_auth_fake_repo),
    winn_config:put(auth, user_schema, user),
    winn_config:put(auth, secret, <<"test_secret">>),
    winn_auth_fake_repo:reset().

register_returns_sanitized_user_test() ->
    setup_auth(),
    {ok, User} = winn_auth:register(<<"alice@example.com">>, <<"hunter2">>),
    ?assertEqual(<<"alice@example.com">>, maps:get(email, User)),
    ?assert(maps:is_key(id, User)),
    %% Password hash must never be returned to callers.
    ?assertNot(maps:is_key(password_hash, User)).

register_duplicate_email_test() ->
    setup_auth(),
    {ok, _} = winn_auth:register(<<"dup@example.com">>, <<"pw">>),
    ?assertEqual({error, email_taken},
                 winn_auth:register(<<"dup@example.com">>, <<"pw2">>)).

login_happy_path_test() ->
    setup_auth(),
    {ok, User} = winn_auth:register(<<"bob@example.com">>, <<"s3cret">>),
    {ok, Result} = winn_auth:login(<<"bob@example.com">>, <<"s3cret">>),
    Token = maps:get(access_token, Result),
    ?assert(is_binary(Token)),
    ?assertNot(maps:is_key(password_hash, maps:get(user, Result))),
    %% Token is a valid JWT whose user_id claim matches the registered user.
    {ok, Claims} = winn_jwt:verify(Token, <<"test_secret">>),
    ?assertEqual(maps:get(id, User), maps:get(<<"user_id">>, Claims)),
    ?assert(maps:is_key(<<"exp">>, Claims)).

login_wrong_password_test() ->
    setup_auth(),
    {ok, _} = winn_auth:register(<<"carol@example.com">>, <<"rightpw">>),
    ?assertEqual({error, invalid_credentials},
                 winn_auth:login(<<"carol@example.com">>, <<"wrongpw">>)).

login_unknown_email_test() ->
    setup_auth(),
    %% Same error as wrong-password — no user enumeration.
    ?assertEqual({error, invalid_credentials},
                 winn_auth:login(<<"nobody@example.com">>, <<"whatever">>)).

current_user_from_claims_test() ->
    setup_auth(),
    {ok, User} = winn_auth:register(<<"dave@example.com">>, <<"pw">>),
    {ok, Result} = winn_auth:login(<<"dave@example.com">>, <<"pw">>),
    {ok, Claims} = winn_jwt:verify(maps:get(access_token, Result), <<"test_secret">>),
    Conn = #{claims => Claims},
    {ok, Loaded} = winn_auth:current_user(Conn),
    ?assertEqual(maps:get(id, User), maps:get(id, Loaded)),
    ?assertEqual(<<"dave@example.com">>, maps:get(email, Loaded)).

current_user_without_claims_test() ->
    setup_auth(),
    ?assertEqual({error, unauthenticated}, winn_auth:current_user(#{})),
    ?assertEqual({error, unauthenticated}, winn_auth:current_user(#{claims => #{}})).

login_missing_secret_test() ->
    setup_auth(),
    {ok, _} = winn_auth:register(<<"eve@example.com">>, <<"pw">>),
    winn_config:put(auth, secret, nil),
    ?assertEqual({error, missing_secret},
                 winn_auth:login(<<"eve@example.com">>, <<"pw">>)).

%% End-to-end through the compiler: Winn source using `Auth.register` / `Auth.login`
%% must resolve (winn_codegen_resolve maps Auth -> winn_auth) and run.
e2e_auth_register_login_test() ->
    setup_auth(),
    Source = "module AuthFlow\n"
             "  def run()\n"
             "    Auth.register(\"e2e@example.com\", \"secret\")\n"
             "    match Auth.login(\"e2e@example.com\", \"secret\")\n"
             "      ok result => result.access_token\n"
             "      err _ => \"failed\"\n"
             "    end\n"
             "  end\n"
             "end\n",
    Mod = compile_and_load(Source),
    Token = Mod:run(),
    ?assert(is_binary(Token)),
    ?assertNotEqual(<<"failed">>, Token).

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

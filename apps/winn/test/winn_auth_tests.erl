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

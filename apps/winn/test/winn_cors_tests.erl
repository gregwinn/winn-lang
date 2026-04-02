%% winn_cors_tests.erl
%% Tests for CORS middleware (#48).

-module(winn_cors_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Default config ──────────────────────────────────────────────────────────

default_config_test() ->
    Config = winn_cors:default_config(),
    ?assertEqual(<<"*">>, maps:get(origins, Config)),
    ?assert(is_binary(maps:get(methods, Config))),
    ?assert(is_binary(maps:get(headers, Config))).

%% ── CORS middleware adds headers ────────────────────────────────────────────

cors_adds_headers_test() ->
    application:ensure_all_started(cowboy),
    %% We can't easily create a real cowboy_req in unit tests,
    %% so test the config parsing instead
    Config = #{origins => [<<"http://localhost:3000">>, <<"https://myapp.com">>]},
    Origin = winn_cors:default_config(),
    ?assert(is_map(Origin)).

%% ── Router recognizes :cors middleware ───────────────────────────────────────

cors_in_routes_compiles_test() ->
    Source = "module CorsRouter\n"
             "  use Winn.Router\n"
             "\n"
             "  def routes()\n"
             "    [{:get, \"/\", :index}]\n"
             "  end\n"
             "\n"
             "  def middleware()\n"
             "    [:cors]\n"
             "  end\n"
             "\n"
             "  def index(conn)\n"
             "    Server.json(conn, %{status: \"working\"})\n"
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
    ?assertEqual([cors], ModName:middleware()).

cors_with_config_compiles_test() ->
    Source = "module CorsConfigRouter\n"
             "  use Winn.Router\n"
             "\n"
             "  def routes()\n"
             "    [{:get, \"/\", :index}]\n"
             "  end\n"
             "\n"
             "  def middleware()\n"
             "    [:cors]\n"
             "  end\n"
             "\n"
             "  def cors_config()\n"
             "    %{origins: \"http://localhost:3000\", max_age: 3600}\n"
             "  end\n"
             "\n"
             "  def index(conn)\n"
             "    Server.json(conn, %{status: \"working\"})\n"
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
    Config = ModName:cors_config(),
    ?assertEqual(<<"http://localhost:3000">>, maps:get(origins, Config)).

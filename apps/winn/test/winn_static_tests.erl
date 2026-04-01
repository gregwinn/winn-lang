%% winn_static_tests.erl
%% Tests for static file serving (#47).

-module(winn_static_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Static route extraction ─────────────────────────────────────────────────

build_static_routes_test() ->
    %% Create a temp directory with a file
    Dir = "/tmp/winn_static_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(Dir),
    file:write_file(Dir ++ "/index.html", <<"<h1>Hello</h1>">>),

    Routes = [{static, "/public", Dir}],
    Result = winn_server:build_static_routes(Routes),
    ?assertEqual(1, length(Result)),

    %% Verify the Cowboy route pattern
    {Pattern, cowboy_static, {dir, _, _}} = hd(Result),
    ?assertEqual("/public/[...]", Pattern),

    os:cmd("rm -rf " ++ Dir).

build_static_routes_nonexistent_dir_test() ->
    Routes = [{static, "/assets", "/nonexistent/path/xyz"}],
    Result = winn_server:build_static_routes(Routes),
    ?assertEqual([], Result).

build_static_routes_mixed_test() ->
    Dir = "/tmp/winn_static_mix_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(Dir),

    Routes = [
        {get, "/api/users", list_users},
        {static, "/public", Dir},
        {post, "/api/users", create_user}
    ],
    Result = winn_server:build_static_routes(Routes),
    %% Only the static route should be extracted
    ?assertEqual(1, length(Result)),

    os:cmd("rm -rf " ++ Dir).

build_static_routes_empty_test() ->
    Result = winn_server:build_static_routes([]),
    ?assertEqual([], Result).

%% ── Router skips static routes ──────────────────────────────────────────────

router_skips_static_test() ->
    %% Static routes should not match in the Winn router
    Routes = [
        {static, "/public", "static/"},
        {get, <<"/api">>, handler}
    ],
    ?assertEqual(nomatch, winn_router:match_route(get, <<"/public/style.css">>, Routes)),
    ?assertMatch({ok, handler, _}, winn_router:match_route(get, <<"/api">>, Routes)).

%% ── Compiles from Winn source ───────────────────────────────────────────────

static_in_routes_compiles_test() ->
    Source = "module StaticRouter\n"
             "  use Winn.Router\n"
             "\n"
             "  def routes()\n"
             "    [\n"
             "      {:static, \"/public\", \"static/\"},\n"
             "      {:get, \"/\", :index}\n"
             "    ]\n"
             "  end\n"
             "\n"
             "  def index(conn)\n"
             "    Server.json(conn, %{status: \"ok\"})\n"
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
    Routes = ModName:routes(),
    ?assertMatch([{static, _, _}, {get, _, _}], Routes).

%% winn_auth_scaffold_tests — `winn create auth` generator (#168). Runs the
%% generator in a temp dir and asserts it produces files that compile.
-module(winn_auth_scaffold_tests).
-include_lib("eunit/include/eunit.hrl").

scaffold_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(_) ->
         [
          {"generates the expected files", fun files_exist/0},
          {"generated controller compiles + has the auth routes", fun controller_ok/0},
          {"generated models compile", fun models_compile/0}
         ]
     end}.

setup() ->
    {ok, Cwd} = file:get_cwd(),
    Tmp = filename:join("/tmp",
        "winn_auth_scaffold_" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_path(Tmp),
    ok = file:set_cwd(Tmp),
    winn_generator:generate(auth, []),
    Cwd.

cleanup(Cwd) ->
    file:set_cwd(Cwd).

files_exist() ->
    ?assert(filelib:is_file("src/models/user.winn")),
    ?assert(filelib:is_file("src/models/auth_token.winn")),
    ?assert(filelib:is_file("src/controllers/auth_controller.winn")),
    ?assertEqual(1, length(filelib:wildcard("db/migrations/*_create_users.winn"))),
    ?assertEqual(1, length(filelib:wildcard("db/migrations/*_create_auth_tokens.winn"))).

controller_ok() ->
    Mod = compile_and_load("src/controllers/auth_controller.winn"),
    ?assertEqual(8, length(Mod:routes())),
    ?assertEqual([cors, auth], Mod:middleware()),
    ?assert(maps:is_key(exclude, Mod:auth_config())).

models_compile() ->
    %% Compile but DON'T load `user` — it would clobber OTP's `user` module.
    {_, UserBin} = compile_only("src/models/user.winn"),
    {_, TokBin}  = compile_only("src/models/auth_token.winn"),
    ?assert(is_binary(UserBin)),
    ?assert(is_binary(TokBin)).

compile_only(Path) ->
    {ok, Bin} = file:read_file(Path),
    {ok, RawTokens, _} = winn_lexer:string(binary_to_list(Bin)),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST} = winn_parser:parse(Tokens),
    Transformed = winn_transform:transform(AST),
    [CoreMod | _] = winn_codegen:gen(Transformed),
    {ok, ModName, Beam} = compile:forms(CoreMod, [from_core, return_errors]),
    {ModName, Beam}.

compile_and_load(Path) ->
    {ModName, Beam} = compile_only(Path),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Beam),
    ModName.

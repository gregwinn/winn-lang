%% winn_r2_tests.erl — R2: UUID generation.

-module(winn_r2_tests).
-include_lib("eunit/include/eunit.hrl").

compile_and_load(Source) ->
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── Direct runtime tests ────────────────────────────────────────────────

uuid_v4_format_test() ->
    UUID = winn_runtime:'uuid.v4'(),
    ?assert(is_binary(UUID)),
    ?assertEqual(36, byte_size(UUID)),
    %% Matches UUID v4 pattern: 8-4-4-4-12 hex chars
    Pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    {ok, Re} = re:compile(Pattern),
    ?assertMatch({match, _}, re:run(UUID, Re)).

uuid_v4_uniqueness_test() ->
    UUIDs = [winn_runtime:'uuid.v4'() || _ <- lists:seq(1, 100)],
    Unique = lists:usort(UUIDs),
    ?assertEqual(100, length(Unique)).

%% ── End-to-end test ─────────────────────────────────────────────────────

e2e_uuid_test() ->
    Src = "module UuidTest\n  def run()\n    UUID.v4()\n  end\nend\n",
    Mod = compile_and_load(Src),
    Result = Mod:run(),
    ?assert(is_binary(Result)),
    ?assertEqual(36, byte_size(Result)).

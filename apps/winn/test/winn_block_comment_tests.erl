%% winn_block_comment_tests.erl
%% Tests for block comments (#40).

-module(winn_block_comment_tests).
-include_lib("eunit/include/eunit.hrl").

lex(Src) ->
    {ok, Tokens, _} = winn_lexer:string(Src),
    Tokens.

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

%% ── Block comment stripped ──────────────────────────────────────────────────

block_comment_single_line_test() ->
    ?assertEqual([], lex("#| this is a block comment |#")).

block_comment_multi_line_test() ->
    ?assertEqual([], lex("#| line one\nline two\nline three |#")).

block_comment_inline_test() ->
    Tokens = lex("42 #| comment |# 99"),
    ?assertMatch([{integer_lit, _, 42}, {integer_lit, _, 99}], Tokens).

block_comment_empty_test() ->
    ?assertEqual([], lex("#||#")).

%% ── Line comments still work ────────────────────────────────────────────────

line_comment_still_works_test() ->
    Tokens = lex("42 # line comment"),
    ?assertMatch([{integer_lit, _, 42}], Tokens).

%% ── End-to-end: module with block comments ──────────────────────────────────

block_comment_in_module_test() ->
    Mod = compile_and_load(
        "module BcMod\n"
        "  #|\n"
        "    This module is just a test.\n"
        "    It has a block comment.\n"
        "  |#\n"
        "\n"
        "  def run()\n"
        "    42\n"
        "  end\n"
        "end\n"),
    ?assertEqual(42, Mod:run()).

block_comment_between_functions_test() ->
    Mod = compile_and_load(
        "module BcBetween\n"
        "  def first()\n"
        "    1\n"
        "  end\n"
        "\n"
        "  #| second function is commented out\n"
        "  def second()\n"
        "    2\n"
        "  end\n"
        "  |#\n"
        "\n"
        "  def third()\n"
        "    3\n"
        "  end\n"
        "end\n"),
    ?assertEqual(1, Mod:first()),
    ?assertEqual(3, Mod:third()).

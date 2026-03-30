%% winn_v04_tests.erl
%% Tests for v0.4.0 language features: pipe assign, triple-quoted strings.

-module(winn_v04_tests).
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

%% ── Pipe assign (|>=) ───────────────────────────────────────────────────────

pipe_assign_lexer_test() ->
    {ok, RawTok_, _} = winn_lexer:string("x |>= y"), Tokens = winn_newline_filter:filter(RawTok_),
    ?assertMatch([{ident,_,x}, {'|>=',_}, {ident,_,y}], Tokens).

pipe_assign_simple_test() ->
    Mod = compile_and_load(
        "module PaSimple\n"
        "  def run()\n"
        "    [1,2,3] |>= items\n"
        "    items\n"
        "  end\n"
        "end\n"),
    ?assertEqual([1,2,3], Mod:run()).

pipe_assign_in_chain_test() ->
    Mod = compile_and_load(
        "module PaChain\n"
        "  def run()\n"
        "    [1,2,3,4,5]\n"
        "      |> Enum.filter() do |x| x > 2 end\n"
        "      |> Enum.map() do |x| x * 10 end\n"
        "      |>= results\n"
        "    results\n"
        "  end\n"
        "end\n"),
    ?assertEqual([30,40,50], Mod:run()).

%% ── Triple-quoted strings ───────────────────────────────────────────────────

triple_string_simple_test() ->
    {ok, RawTok_, _} = winn_lexer:string("\"\"\"hello world\"\"\""), Tokens = winn_newline_filter:filter(RawTok_),
    ?assertMatch([{string_lit, _, <<"hello world">>}], Tokens).

triple_string_embedded_quotes_test() ->
    {ok, RawTok_, _} = winn_lexer:string("\"\"\"say \"hello\" world\"\"\""), Tokens = winn_newline_filter:filter(RawTok_),
    ?assertMatch([{string_lit, _, <<"say \"hello\" world">>}], Tokens).

triple_string_multiline_dedent_test() ->
    {ok, RawTok_, _} = winn_lexer:string("\"\"\"\n  line one\n  line two\n\"\"\""), Tokens = winn_newline_filter:filter(RawTok_),
    ?assertMatch([{string_lit, _, <<"line one\nline two">>}], Tokens).

triple_string_compiles_test() ->
    Mod = compile_and_load(
        "module TripleComp\n"
        "  def run()\n"
        "    \"\"\"\n"
        "    SELECT *\n"
        "    FROM users\n"
        "    \"\"\"\n"
        "  end\n"
        "end\n"),
    ?assertEqual(<<"SELECT *\nFROM users">>, Mod:run()).

triple_string_interpolation_test() ->
    Mod = compile_and_load(
        "module TripleInterp\n"
        "  def run()\n"
        "    name = \"Alice\"\n"
        "    \"\"\"hello #{name}!\"\"\"\n"
        "  end\n"
        "end\n"),
    ?assertEqual(<<"hello Alice!">>, Mod:run()).

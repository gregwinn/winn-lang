%% winn_lexer_tests.erl
%% EUnit tests for the Winn lexer.

-module(winn_lexer_tests).
-include_lib("eunit/include/eunit.hrl").

%% Helper: lex a string and return only the token tuples (drop EOF).
lex(Src) ->
    {ok, Tokens, _} = winn_lexer:string(Src),
    Tokens.

%% ── Whitespace and comments ───────────────────────────────────────────────

whitespace_skipped_test() ->
    ?assertEqual([], lex("   \t\r  ")).

whitespace_newline_emits_token_test() ->
    ?assertMatch([{newline, _}], lex("\n")).

comment_skipped_test() ->
    ?assertEqual([{newline, 1}], lex("# this is a comment\n")).

comment_inline_test() ->
    Tokens = lex("42 # comment"),
    ?assertMatch([{integer_lit, 1, 42}], Tokens).

%% ── Keywords ──────────────────────────────────────────────────────────────

keywords_test() ->
    Src = "module def do end match ok err true false nil",
    Tokens = lex(Src),
    Tags = [element(1, T) || T <- Tokens],
    ?assertEqual(
        ['module', 'def', 'do', 'end', 'match', 'ok_kw', 'err_kw',
         boolean_lit, boolean_lit, 'nil_kw'],
        Tags
    ).

keyword_not_prefix_test() ->
    %% "modules" should be an ident, not the "module" keyword + "s".
    Tokens = lex("modules"),
    ?assertMatch([{ident, 1, modules}], Tokens).

%% ── Identifiers ───────────────────────────────────────────────────────────

lowercase_ident_test() ->
    ?assertMatch([{ident, 1, hello}], lex("hello")).

underscore_ident_test() ->
    ?assertMatch([{ident, 1, '_foo'}], lex("_foo")).

module_name_test() ->
    ?assertMatch([{module_name, 1, 'Hello'}], lex("Hello")).

module_name_with_underscore_test() ->
    ?assertMatch([{module_name, 1, 'Hello_World'}], lex("Hello_World")).

%% ── Literals ──────────────────────────────────────────────────────────────

integer_test() ->
    ?assertMatch([{integer_lit, 1, 42}], lex("42")).

negative_integer_test() ->
    %% The minus sign is a separate token; negation is parsed, not lexed.
    Tokens = lex("-7"),
    ?assertMatch([{'-', 1}, {integer_lit, 1, 7}], Tokens).

float_test() ->
    ?assertMatch([{float_lit, 1, 3.14}], lex("3.14")).

string_test() ->
    ?assertMatch([{string_lit, 1, <<"hello">>}], lex("\"hello\"")).

string_escape_test() ->
    [{string_lit, 1, Val}] = lex("\"hi\\nthere\""),
    ?assertEqual(<<"hi\nthere">>, Val).

%% Each supported escape decodes to the expected byte. Source uses Erlang
%% string syntax, so `\\\"` is the two-char Winn source `\"`.
string_escape_dquote_test() ->
    [{string_lit, 1, Val}] = lex("\"he said \\\"hi\\\"\""),
    ?assertEqual(<<"he said \"hi\"">>, Val).

string_escape_backslash_test() ->
    [{string_lit, 1, Val}] = lex("\"a\\\\b\""),
    ?assertEqual(<<"a\\b">>, Val).

string_escape_tab_test() ->
    [{string_lit, 1, Val}] = lex("\"a\\tb\""),
    ?assertEqual(<<"a\tb">>, Val).

string_escape_cr_test() ->
    [{string_lit, 1, Val}] = lex("\"a\\rb\""),
    ?assertEqual(<<"a\rb">>, Val).

string_escape_null_test() ->
    [{string_lit, 1, Val}] = lex("\"a\\0b\""),
    ?assertEqual(<<"a", 0, "b">>, Val).

%% Interpolated strings route through the same unescape helper.
string_escape_in_interpolation_test() ->
    Tokens = lex("\"#{name} said \\\"hi\\\"\""),
    [{interp_string, 1, Parts}] = Tokens,
    ?assertMatch([{expr, "name"}, {str, <<" said \"hi\"">>}], Parts).

%% Prometheus exposition format — the use case that motivated the issue.
string_prometheus_label_test() ->
    [{string_lit, 1, Val}] = lex("\"http_requests_total{endpoint=\\\"GET /users\\\"} 42\""),
    ?assertEqual(<<"http_requests_total{endpoint=\"GET /users\"} 42">>, Val).

atom_lit_test() ->
    ?assertMatch([{atom_lit, 1, ok}],    lex(":ok")).

atom_lit_error_test() ->
    ?assertMatch([{atom_lit, 1, error}], lex(":error")).

boolean_true_test() ->
    ?assertMatch([{boolean_lit, 1, true}],  lex("true")).

boolean_false_test() ->
    ?assertMatch([{boolean_lit, 1, false}], lex("false")).

nil_test() ->
    ?assertMatch([{'nil_kw', 1}], lex("nil")).

%% ── Operators ─────────────────────────────────────────────────────────────

pipe_test() ->
    ?assertMatch([{'|>', 1}], lex("|>")).

fat_arrow_test() ->
    ?assertMatch([{'=>', 1}], lex("=>")).

concat_test() ->
    ?assertMatch([{'<>', 1}], lex("<>")).

eq_test()  -> ?assertMatch([{'==', 1}], lex("==")).
neq_test() -> ?assertMatch([{'!=', 1}], lex("!=")).
lte_test() -> ?assertMatch([{'<=', 1}], lex("<=")).
gte_test() -> ?assertMatch([{'>=', 1}], lex(">=")).

arithmetic_test() ->
    Tokens = lex("+ - * /"),
    ?assertMatch([{'+',1},{'-',1},{'*',1},{'/',1}], Tokens).

%% ── Punctuation ───────────────────────────────────────────────────────────

parens_test() ->
    ?assertMatch([{'(',1},{')',1}], lex("()")).

brackets_test() ->
    ?assertMatch([{'[',1},{']',1}], lex("[]")).

braces_test() ->
    ?assertMatch([{'{',1},{'}',1}], lex("{}")).

dot_test() ->
    ?assertMatch([{'.',1}], lex(".")).

comma_test() ->
    ?assertMatch([{',',1}], lex(",")).

%% ── Full expression tokenisation ──────────────────────────────────────────

module_call_test() ->
    Tokens = lex("IO.puts(\"Hello\")"),
    ?assertMatch(
        [{module_name, 1, 'IO'}, {'.', 1}, {ident, 1, puts},
         {'(', 1}, {string_lit, 1, <<"Hello">>}, {')', 1}],
        Tokens
    ).

pipe_chain_test() ->
    Tokens = lex("x |> trim() |> upcase()"),
    Tags = [element(1, T) || T <- Tokens],
    ?assertEqual(
        [ident, '|>', ident, '(', ')', '|>', ident, '(', ')'],
        Tags
    ).

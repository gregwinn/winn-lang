%% winn_repl_tests.erl — N2: REPL tests.
%% Tests the REPL compilation/eval internals (not the interactive loop).

-module(winn_repl_tests).
-include_lib("eunit/include/eunit.hrl").

%% Helper: build source, compile, and eval — simulating one REPL step.
eval(Input) ->
    eval(Input, #{}).

eval(Input, Bindings) ->
    ModName = "WinnReplTest" ++ integer_to_list(erlang:unique_integer([positive])),
    ModAtom = list_to_atom(string:lowercase(ModName)),
    Source = winn_repl_build_source(ModName, Input, Bindings),
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, _, Bin}    = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModAtom),
    {module, ModAtom} = code:load_binary(ModAtom, "repl_test", Bin),
    Result = ModAtom:'__eval__'(),
    code:purge(ModAtom),
    code:delete(ModAtom),
    Result.

%% Replicate build_source since it's not exported.
winn_repl_build_source(ModName, Input, Bindings) ->
    winn_repl:ensure_binding_table_test(),
    maps:foreach(fun(Name, Value) ->
        ets:insert(winn_repl_bindings, {Name, Value})
    end, Bindings),
    BindingLines = maps:fold(fun(Name, _Value, Acc) ->
        Line = io_lib:format("    ~s = ReplBindings.get(\"~s\")\n", [Name, Name]),
        [Line | Acc]
    end, [], Bindings),
    lists:flatten([
        "module ", ModName, "\n",
        "  def __eval__()\n",
        BindingLines,
        "    ", Input, "\n",
        "  end\n",
        "end\n"
    ]).

%% ── Basic expression tests ──────────────────────────────────────────────

arithmetic_test() ->
    ?assertEqual(3, eval("1 + 2")).

string_test() ->
    ?assertEqual(<<"hello">>, eval("\"hello\"")).

atom_test() ->
    ?assertEqual(ok, eval(":ok")).

list_test() ->
    ?assertEqual([1, 2, 3], eval("[1, 2, 3]")).

boolean_test() ->
    ?assertEqual(true, eval("true")).

nil_test() ->
    ?assertEqual(nil, eval("nil")).

%% ── Variable binding tests ──────────────────────────────────────────────

variable_assignment_test() ->
    ?assertEqual(42, eval("x = 42")).

variable_in_expression_test() ->
    ?assertEqual(52, eval("x + 10", #{"x" => 42})).

multiple_bindings_test() ->
    ?assertEqual(7, eval("a + b", #{"a" => 3, "b" => 4})).

string_binding_test() ->
    ?assertEqual(<<"Hello, Alice!">>, eval("\"Hello, #{name}!\"", #{"name" => <<"Alice">>})).

%% ── Complex expression tests ────────────────────────────────────────────

range_test() ->
    ?assertEqual([1, 2, 3, 4, 5], eval("1..5")).

for_comprehension_test() ->
    ?assertEqual([1, 4, 9], eval("for x in [1, 2, 3] do x * x end")).

enum_test() ->
    ?assertEqual([2, 4, 6], eval("Enum.map([1, 2, 3]) do |x| x * 2 end")).

if_else_test() ->
    ?assertEqual(yes, eval("if true\n  :yes\nelse\n  :no\nend")).

%% ── Incomplete input detection ──────────────────────────────────────────

incomplete_open_paren_test() ->
    ?assert(is_incomplete("Enum.map([1, 2, 3]")).

incomplete_pipe_test() ->
    ?assert(is_incomplete("[1, 2] |>")).

complete_expression_test() ->
    ?assertNot(is_incomplete("1 + 2")).

complete_string_test() ->
    ?assertNot(is_incomplete("\"hello\"")).

is_incomplete(Input) ->
    %% Replicate the check from winn_repl
    Opens  = count_char(Input, $() + count_char(Input, $[) + count_char(Input, ${),
    Closes = count_char(Input, $)) + count_char(Input, $]) + count_char(Input, $}),
    case Opens > Closes of
        true -> true;
        false ->
            Last = string:trim(Input, trailing),
            lists:any(fun(Suffix) -> lists:suffix(Suffix, Last) end,
                      ["|>", "=>", "->", "<>", "+", "-", "*", "/",
                       "=", "and", "or", "do", ","])
    end.

count_char([], _) -> 0;
count_char([C | Rest], C) -> 1 + count_char(Rest, C);
count_char([_ | Rest], C) -> count_char(Rest, C).

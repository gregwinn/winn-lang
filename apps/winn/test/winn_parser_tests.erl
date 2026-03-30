%% winn_parser_tests.erl
%% EUnit tests for the Winn parser.

-module(winn_parser_tests).
-include_lib("eunit/include/eunit.hrl").

%% Helper: lex + parse a string and return the AST.
parse(Src) ->
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    {ok, Forms}     = winn_parser:parse(Tokens),
    Forms.

%% ── Module ────────────────────────────────────────────────────────────────

empty_module_test() ->
    [{module, 1, 'Hello', []}] = parse("module Hello end").

module_with_function_test() ->
    [{module, _, 'Blog', [Fun]}] = parse(
        "module Blog\n"
        "  def greet() end\n"
        "end"
    ),
    ?assertMatch({function, _, greet, [], []}, Fun).

%% ── Function definitions ──────────────────────────────────────────────────

no_params_function_test() ->
    [Form] = parse("module M def foo() end end"),
    {module, _, 'M', [Fun]} = Form,
    ?assertMatch({function, _, foo, [], []}, Fun).

one_param_function_test() ->
    [Form] = parse("module M def foo(x) end end"),
    {module, _, 'M', [Fun]} = Form,
    {function, _, foo, Params, _} = Fun,
    ?assertMatch([{var, _, x}], Params).

two_param_function_test() ->
    [Form] = parse("module M def add(a, b) end end"),
    {module, _, 'M', [Fun]} = Form,
    {function, _, add, Params, _} = Fun,
    ?assertEqual(2, length(Params)).

%% ── Literals ──────────────────────────────────────────────────────────────

string_literal_test() ->
    [Form] = parse("module M def f() \"hello\" end end"),
    {module,_,'M',[{function,_,f,[],[Lit]}]} = Form,
    ?assertMatch({string, _, <<"hello">>}, Lit).

integer_literal_test() ->
    [Form] = parse("module M def f() 42 end end"),
    {module,_,'M',[{function,_,f,[],[Lit]}]} = Form,
    ?assertMatch({integer, _, 42}, Lit).

atom_literal_test() ->
    [Form] = parse("module M def f() :ok end end"),
    {module,_,'M',[{function,_,f,[],[Lit]}]} = Form,
    ?assertMatch({atom, _, ok}, Lit).

bool_true_test() ->
    [Form] = parse("module M def f() true end end"),
    {module,_,'M',[{function,_,f,[],[Lit]}]} = Form,
    ?assertMatch({boolean, _, true}, Lit).

nil_literal_test() ->
    [Form] = parse("module M def f() nil end end"),
    {module,_,'M',[{function,_,f,[],[Lit]}]} = Form,
    ?assertMatch({nil, _}, Lit).

list_literal_test() ->
    [Form] = parse("module M def f() [1, 2, 3] end end"),
    {module,_,'M',[{function,_,f,[],[Lit]}]} = Form,
    ?assertMatch({list, _, [{integer,_,1},{integer,_,2},{integer,_,3}]}, Lit).

tuple_literal_test() ->
    [Form] = parse("module M def f() {:ok, 42} end end"),
    {module,_,'M',[{function,_,f,[],[Lit]}]} = Form,
    ?assertMatch({tuple, _, [{atom,_,ok},{integer,_,42}]}, Lit).

%% ── Function calls ────────────────────────────────────────────────────────

local_call_test() ->
    [Form] = parse("module M def f() save() end end"),
    {module,_,'M',[{function,_,f,[],[Call]}]} = Form,
    ?assertMatch({call, _, save, []}, Call).

local_call_with_args_test() ->
    [Form] = parse("module M def f() add(1, 2) end end"),
    {module,_,'M',[{function,_,f,[],[Call]}]} = Form,
    ?assertMatch({call, _, add, [{integer,_,1},{integer,_,2}]}, Call).

dot_call_test() ->
    [Form] = parse("module M def f() IO.puts(\"hi\") end end"),
    {module,_,'M',[{function,_,f,[],[Call]}]} = Form,
    ?assertMatch({dot_call, _, 'IO', puts, [{string,_,<<"hi">>}]}, Call).

%% ── Operators ─────────────────────────────────────────────────────────────

addition_test() ->
    [Form] = parse("module M def f() 1 + 2 end end"),
    {module,_,'M',[{function,_,f,[],[Expr]}]} = Form,
    ?assertMatch({op, _, '+', {integer,_,1}, {integer,_,2}}, Expr).

pipe_test() ->
    [Form] = parse("module M def f() x |> trim() end end"),
    {module,_,'M',[{function,_,f,[],[Expr]}]} = Form,
    ?assertMatch({pipe, _, {var,_,x}, {call,_,trim,[]}}, Expr).

pipe_chain_test() ->
    [Form] = parse("module M def f() x |> trim() |> upcase() end end"),
    {module,_,'M',[{function,_,f,[],[Expr]}]} = Form,
    %% Left-associative: (x |> trim()) |> upcase()
    ?assertMatch({pipe, _, {pipe,_,{var,_,x},{call,_,trim,[]}}, {call,_,upcase,[]}}, Expr).

string_concat_test() ->
    [Form] = parse("module M def f() \"a\" <> \"b\" end end"),
    {module,_,'M',[{function,_,f,[],[Expr]}]} = Form,
    ?assertMatch({op, _, '<>', {string,_,<<"a">>}, {string,_,<<"b">>}}, Expr).

%% ── Multi-expression body ─────────────────────────────────────────────────

multi_expr_body_test() ->
    [Form] = parse("module M def f() 1 2 3 end end"),
    {module,_,'M',[{function,_,f,[],Body}]} = Form,
    ?assertEqual(3, length(Body)).

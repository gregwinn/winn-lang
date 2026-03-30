%% winn_phase2_tests.erl
%% EUnit tests for Phase 2: pattern matching and match blocks.

-module(winn_phase2_tests).
-include_lib("eunit/include/eunit.hrl").

%% Helpers
lex(Src) ->
    {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_),
    Tokens.

parse(Src) ->
    {ok, Forms} = winn_parser:parse(lex(Src)),
    Forms.

transform(Src) ->
    winn_transform:transform(parse(Src)).

compile_to_binary(Src) ->
    Forms    = transform(Src),
    CoreMods = winn_codegen:gen(Forms),
    [begin
         {ok, _, Bin} = winn_core_emit:emit_to_binary(M),
         Bin
     end || M <- CoreMods].

%% Compile Winn source, load the module in-memory, and return the module name.
load_src(Src) ->
    Forms    = transform(Src),
    CoreMods = winn_codegen:gen(Forms),
    [CoreMod | _] = CoreMods,
    {ok, ModName, Bin} = winn_core_emit:emit_to_binary(CoreMod),
    {module, ModName} = code:load_binary(ModName, "nofile", Bin),
    ModName.

%% ── Lexer tests for Phase 2 tokens ───────────────────────────────────────

lex_match_test() ->
    Tokens = lex("match ok err =>"),
    Tags = [element(1, T) || T <- Tokens],
    ?assertEqual(['match', 'ok_kw', 'err_kw', '=>'], Tags).

%% ── Parser tests for patterns ─────────────────────────────────────────────

parse_tuple_pattern_test() ->
    Src = "module M def f({:ok, val}) end end",
    [{module, _, 'M', [{function, _, f, [Pat], []}]}] = parse(Src),
    ?assertMatch({pat_tuple, _, [{pat_atom, _, ok}, {var, _, val}]}, Pat).

parse_atom_pattern_test() ->
    Src = "module M def f(:ok) end end",
    [{module, _, 'M', [{function, _, f, [Pat], []}]}] = parse(Src),
    ?assertMatch({pat_atom, _, ok}, Pat).

parse_integer_pattern_test() ->
    Src = "module M def f(0) end end",
    [{module, _, 'M', [{function, _, f, [Pat], []}]}] = parse(Src),
    ?assertMatch({pat_integer, _, 0}, Pat).

parse_negative_integer_pattern_test() ->
    Src = "module M def f(-1) end end",
    [{module, _, 'M', [{function, _, f, [Pat], []}]}] = parse(Src),
    ?assertMatch({pat_integer, _, -1}, Pat).

parse_wildcard_pattern_test() ->
    Src = "module M def f(_) end end",
    [{module, _, 'M', [{function, _, f, [Pat], []}]}] = parse(Src),
    ?assertMatch({pat_wildcard, _}, Pat).

parse_list_pattern_empty_test() ->
    Src = "module M def f([]) end end",
    [{module, _, 'M', [{function, _, f, [Pat], []}]}] = parse(Src),
    ?assertMatch({pat_list, _, [], nil}, Pat).

parse_list_pattern_test() ->
    Src = "module M def f([h | t]) end end",
    [{module, _, 'M', [{function, _, f, [Pat], []}]}] = parse(Src),
    ?assertMatch({pat_list, _, [{var,_,h}], {var,_,t}}, Pat).

parse_nested_tuple_pattern_test() ->
    Src = "module M def f({:ok, {:user, name}}) end end",
    [{module, _, 'M', [{function, _, f, [Pat], []}]}] = parse(Src),
    {pat_tuple, _, [{pat_atom,_,ok}, {pat_tuple,_,[{pat_atom,_,user},{var,_,name}]}]} = Pat,
    ok.

%% ── Parser tests for match blocks ────────────────────────────────────────

parse_match_block_pipe_test() ->
    Src = "module M def f(x) x |> match ok v => v err e => e end end end",
    [{module, _, 'M', [{function, _, f, _, Body}]}] = parse(Src),
    [{pipe, _, {var,_,x}, {match_block,_,none,Clauses}}] = Body,
    ?assertEqual(2, length(Clauses)).

parse_match_block_standalone_test() ->
    Src = "module M def f(x) match x ok v => v err e => e end end end",
    [{module, _, 'M', [{function, _, f, _, Body}]}] = parse(Src),
    [{match_block, _, {var,_,x}, Clauses}] = Body,
    ?assertEqual(2, length(Clauses)).

parse_match_clause_ok_test() ->
    Src = "module M def f(x) x |> match ok val => val end end end",
    [{module,_,'M',[{function,_,f,_,[{pipe,_,_,{match_block,_,none,[Clause]}}]}]}] = parse(Src),
    ?assertMatch({match_clause, _, ok, {var,_,val}, [{var,_,val}]}, Clause).

parse_match_clause_err_test() ->
    Src = "module M def f(x) x |> match err e => e end end end",
    [{module,_,'M',[{function,_,f,_,[{pipe,_,_,{match_block,_,none,[Clause]}}]}]}] = parse(Src),
    ?assertMatch({match_clause, _, err, {var,_,e}, [{var,_,e}]}, Clause).

%% ── Transform tests ───────────────────────────────────────────────────────

transform_pattern_wrap_test() ->
    Src = "module M def f({:ok, v}) v end end",
    [{module,_,'M',[Fun]}] = transform(Src),
    {function, _, f, [{var,_,'_arg0'}], [{case_expr,_,{var,_,'_arg0'},[Clause]}]} = Fun,
    {case_clause, _, [{pat_tuple,_,[{pat_atom,_,ok},{var,_,v}]}], none, [{var,_,v}]} = Clause,
    ok.

transform_pipe_match_test() ->
    Src = "module M def f(x) x |> match ok v => v err e => e end end end",
    [{module,_,'M',[{function,_,f,[_],[OuterCase]}]}] = transform(Src),
    %% Outer case wraps the param, inner case is the pipe-match.
    {case_expr, _, _, [{case_clause, _, _, _, [InnerCase]}]} = OuterCase,
    {case_expr, _, _, [C1, C2]} = InnerCase,
    ?assertMatch({case_clause,_,[{pat_tuple,_,[{pat_atom,_,ok},_]}],_,_}, C1),
    ?assertMatch({case_clause,_,[{pat_tuple,_,[{pat_atom,_,error},_]}],_,_}, C2).

transform_multi_clause_merge_test() ->
    Src = "module M\n"
          "  def describe({:ok, _}) \"ok\" end\n"
          "  def describe({:error, _}) \"error\" end\n"
          "end",
    [{module,_,'M',[Fun]}] = transform(Src),
    %% Should be merged into a single function with two case clauses.
    {function, _, describe, [_], [{case_expr, _, _, Clauses}]} = Fun,
    ?assertEqual(2, length(Clauses)).

%% ── End-to-end compilation + execution tests ─────────────────────────────

compile_and_run_basic_pattern_test() ->
    Src = "module Result\n"
          "  def unwrap({:ok, val}) val end\n"
          "  def unwrap({:error, _}) :failed end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(42,      ModName:unwrap({ok, 42})),
    ?assertEqual(failed,  ModName:unwrap({error, <<"oops">>})).

compile_and_run_wildcard_test() ->
    Src = "module Wildcard\n"
          "  def ignore(_) :ok end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(ok, ModName:ignore(anything)),
    ?assertEqual(ok, ModName:ignore(42)).

compile_and_run_atom_pattern_test() ->
    Src = "module Flag\n"
          "  def label(:ok) \"success\" end\n"
          "  def label(:error) \"failure\" end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(<<"success">>, ModName:label(ok)),
    ?assertEqual(<<"failure">>, ModName:label(error)).

compile_and_run_match_block_test() ->
    Src = "module Pipeline\n"
          "  def run(x)\n"
          "    x\n"
          "      |> match\n"
          "        ok v   => v\n"
          "        err e  => e\n"
          "      end\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(99,           ModName:run({ok, 99})),
    ?assertEqual(<<"oops">>,   ModName:run({error, <<"oops">>})).

compile_and_run_standalone_match_test() ->
    Src = "module StandAlone\n"
          "  def check(x)\n"
          "    match x\n"
          "      ok v  => v\n"
          "      err _ => :failed\n"
          "    end\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(hello,   ModName:check({ok, hello})),
    ?assertEqual(failed,  ModName:check({error, <<"whatever">>})).

compile_and_run_nested_pattern_test() ->
    Src = "module Nested\n"
          "  def name({:ok, {:user, n}}) n end\n"
          "  def name({:error, _}) :unknown end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(alice,   ModName:name({ok, {user, alice}})),
    ?assertEqual(unknown, ModName:name({error, <<"not found">>})).

%% ── Phase 2 milestone: Blog.create/1 shape compiles ──────────────────────

blog_create_compiles_test() ->
    %% The Blog.create/1 pattern from the plan (without actual Repo — just
    %% verifies the pipe + match structure compiles to a .beam).
    Src = "module Demo\n"
          "  def describe(result)\n"
          "    result\n"
          "      |> match\n"
          "        ok v  => v\n"
          "        err _ => :error\n"
          "      end\n"
          "  end\n"
          "end",
    [Bin] = compile_to_binary(Src),
    ?assert(is_binary(Bin)).

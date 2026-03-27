-module(winn_phase3_tests).
-include_lib("eunit/include/eunit.hrl").

lex(Src) -> {ok, Tokens, _} = winn_lexer:string(Src), Tokens.
parse(Src) -> {ok, Forms} = winn_parser:parse(lex(Src)), Forms.
transform(Src) -> winn_transform:transform(parse(Src)).
compile_to_binary(Src) ->
    Forms = transform(Src),
    CoreMods = winn_codegen:gen(Forms),
    [Bin || {ok, _, Bin} <- [winn_core_emit:emit_to_binary(M) || M <- CoreMods]].
load_src(Src) ->
    Forms = transform(Src),
    [CoreMod | _] = winn_codegen:gen(Forms),
    {ok, ModName, Bin} = winn_core_emit:emit_to_binary(CoreMod),
    {module, ModName} = code:load_binary(ModName, "nofile", Bin),
    ModName.

%% ── Parser tests ─────────────────────────────────────────────────────────

parse_block_call_test() ->
    Src = "module M def f(list) Enum.map(list) do |x| x end end end",
    [{module,_,'M',[{function,_,f,_,[Expr]}]}] = parse(Src),
    ?assertMatch({block_call, _, {dot_call,_,'Enum',map,[{var,_,list}]}, [{var,_,x}], [{var,_,x}]}, Expr).

parse_block_no_params_test() ->
    Src = "module M def f() IO.puts(\"hi\") do end end end",
    [{module,_,'M',[{function,_,f,_,[Expr]}]}] = parse(Src),
    ?assertMatch({block_call, _, {dot_call,_,'IO',puts,_}, [], []}, Expr).

parse_block_multi_params_test() ->
    Src = "module M def f(list) Enum.reduce(list, 0) do |x, acc| x + acc end end end",
    [{module,_,'M',[{function,_,f,_,[Expr]}]}] = parse(Src),
    ?assertMatch({block_call, _, _, [{var,_,x},{var,_,acc}], _}, Expr).

%% ── Transform tests ──────────────────────────────────────────────────────

transform_block_call_test() ->
    Src = "module M def f(list) Enum.map(list) do |x| x end end end",
    [{module,_,'M',[{function,_,f,_,[OuterCase]}]}] = transform(Src),
    %% Body is case-wrapped; inner expression is the dot_call with block
    {case_expr, _, _, [{case_clause, _, _, _, [Expr]}]} = OuterCase,
    ?assertMatch({dot_call, _, 'Enum', map, [{var,_,list}, {block,_,[{var,_,x}],[{var,_,x}]}]}, Expr).

transform_pipe_block_test() ->
    Src = "module M def f(list) list |> Enum.map() do |x| x * 2 end end end",
    [{module,_,'M',[{function,_,f,_,[OuterCase]}]}] = transform(Src),
    {case_expr, _, _, [{case_clause, _, _, _, [Expr]}]} = OuterCase,
    ?assertMatch({dot_call, _, 'Enum', map, [{var,_,list}, {block,_,_,_}]}, Expr).

%% ── End-to-end tests ─────────────────────────────────────────────────────

enum_map_test() ->
    Src = "module Col\n"
          "  def double(list)\n"
          "    Enum.map(list) do |x| x * 2 end\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual([2, 4, 6], ModName:double([1, 2, 3])).

enum_filter_test() ->
    Src2 = "module Fil\n"
           "  def big(list)\n"
           "    Enum.filter(list) do |x| x > 2 end\n"
           "  end\n"
           "end",
    ModName = load_src(Src2),
    ?assertEqual([3, 4, 5], ModName:big([1, 2, 3, 4, 5])).

enum_reduce_test() ->
    Src = "module Sum\n"
          "  def total(list)\n"
          "    Enum.reduce(list, 0) do |x, acc| x + acc end\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(15, ModName:total([1, 2, 3, 4, 5])).

pipe_with_blocks_test() ->
    Src = "module Chain\n"
          "  def run(list)\n"
          "    list\n"
          "      |> Enum.filter() do |x| x > 1 end\n"
          "      |> Enum.map() do |x| x * 10 end\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual([20, 30], ModName:run([1, 2, 3])).

hello_still_works_test() ->
    Src = "module Hello\n"
          "  def main()\n"
          "    IO.puts(\"Hello, World!\")\n"
          "  end\n"
          "end",
    [Bin] = compile_to_binary(Src),
    ?assert(is_binary(Bin)).

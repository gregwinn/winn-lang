%% winn_mi_tests.erl — MI2-MI4: Medium-impact feature tests.
%% MI2: to_string/to_integer callable from Winn
%% MI3: Range literals (1..10)
%% MI4: Multi-line switch/rescue bodies

-module(winn_mi_tests).
-include_lib("eunit/include/eunit.hrl").

compile_and_load(Source) ->
    {ok, Tokens, _} = winn_lexer:string(Source),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── MI2: Type conversion builtins ───────────────────────────────────────

to_string_int_test() ->
    Src = "module TsInt\n  def run()\n    to_string(42)\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"42">>, Mod:run()).

to_string_atom_test() ->
    Src = "module TsAtom\n  def run()\n    to_string(:hello)\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"hello">>, Mod:run()).

to_integer_string_test() ->
    Src = "module TiStr\n  def run()\n    to_integer(\"123\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(123, Mod:run()).

to_float_int_test() ->
    Src = "module TfInt\n  def run()\n    to_float(5)\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(5.0, Mod:run()).

to_string_in_interpolation_test() ->
    Src = "module TsInterp\n  def run(n)\n    \"count: #{to_string(n)}\"\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"count: 42">>, Mod:run(42)).

inspect_builtin_test() ->
    Src = "module InspBuilt\n  def run()\n    inspect({:ok, 42})\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assert(is_binary(Mod:run())).

%% ── MI3: Range literals ─────────────────────────────────────────────────

range_lex_test() ->
    {ok, Tokens, _} = winn_lexer:string("1..5"),
    ?assertMatch([{integer_lit, _, 1}, {'..', _}, {integer_lit, _, 5}], Tokens).

range_basic_test() ->
    Src = "module RangeBasic\n  def run()\n    1..5\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual([1, 2, 3, 4, 5], Mod:run()).

range_single_test() ->
    Src = "module RangeSingle\n  def run()\n    3..3\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual([3], Mod:run()).

range_with_for_test() ->
    Src = "module RangeFor\n  def run()\n    for i in 1..4 do i * 10 end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual([10, 20, 30, 40], Mod:run()).

range_dynamic_test() ->
    Src = "module RangeDyn\n  def run(n)\n    1..n\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual([1, 2, 3], Mod:run(3)).

range_in_pipe_test() ->
    Src = "module RangePipe\n  def run()\n    1..5\n      |> Enum.map() do |x| x * 2 end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual([2, 4, 6, 8, 10], Mod:run()).

%% ── MI4: Multi-line switch/rescue bodies ────────────────────────────────

multiline_switch_test() ->
    Src = "module MlSwitch\n"
          "  def run(x)\n"
          "    switch x\n"
          "      :a => do\n"
          "        y = 10\n"
          "        y + 1\n"
          "      end\n"
          "      _ => 0\n"
          "    end\n"
          "  end\n"
          "end\n",
    Mod = compile_and_load(Src),
    ?assertEqual(11, Mod:run(a)),
    ?assertEqual(0, Mod:run(b)).

multiline_switch_guard_test() ->
    Src = "module MlSwGuard\n"
          "  def run(n)\n"
          "    switch n\n"
          "      x when x > 0 => do\n"
          "        label = :positive\n"
          "        label\n"
          "      end\n"
          "      _ => :other\n"
          "    end\n"
          "  end\n"
          "end\n",
    Mod = compile_and_load(Src),
    ?assertEqual(positive, Mod:run(5)),
    ?assertEqual(other, Mod:run(-1)).

multiline_rescue_test() ->
    Src = "module MlRescue\n"
          "  def run()\n"
          "    try\n"
          "      Erlang.throw(:boom)\n"
          "    rescue\n"
          "      _ => do\n"
          "        msg = \"caught\"\n"
          "        msg\n"
          "      end\n"
          "    end\n"
          "  end\n"
          "end\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"caught">>, Mod:run()).

single_line_still_works_test() ->
    %% Verify single-expression clauses still work.
    Src = "module SlSwitch\n  def run(x)\n    switch x\n      :a => 1\n      _ => 0\n    end\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(1, Mod:run(a)),
    ?assertEqual(0, Mod:run(b)).

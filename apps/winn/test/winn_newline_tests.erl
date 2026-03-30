%% winn_newline_tests.erl
%% Tests for significant newlines (#15).

-module(winn_newline_tests).
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

%% ── Switch: multi-expression without do...end ──────────────────────────────

switch_multiline_no_do_end_test() ->
    Mod = compile_and_load(
        "module NlSw1\n"
        "  def run(x)\n"
        "    switch x\n"
        "      :a =>\n"
        "        y = 10\n"
        "        y + 1\n"
        "      _ => 0\n"
        "    end\n"
        "  end\n"
        "end\n"),
    ?assertEqual(11, Mod:run(a)),
    ?assertEqual(0, Mod:run(b)).

%% ── Switch: old do...end syntax still works ─────────────────────────────────

switch_do_end_backward_compat_test() ->
    Mod = compile_and_load(
        "module NlSw2\n"
        "  def run(x)\n"
        "    switch x\n"
        "      :a => do\n"
        "        y = 10\n"
        "        y + 1\n"
        "      end\n"
        "      _ => 0\n"
        "    end\n"
        "  end\n"
        "end\n"),
    ?assertEqual(11, Mod:run(a)),
    ?assertEqual(0, Mod:run(b)).

%% ── Switch: single expression still works ───────────────────────────────────

switch_single_expr_test() ->
    Mod = compile_and_load(
        "module NlSw3\n"
        "  def run(x)\n"
        "    switch x\n"
        "      :a => 42\n"
        "      _ => 0\n"
        "    end\n"
        "  end\n"
        "end\n"),
    ?assertEqual(42, Mod:run(a)).

%% ── Switch: multi-clause with guards ────────────────────────────────────────

switch_with_guards_test() ->
    Mod = compile_and_load(
        "module NlSw4\n"
        "  def run(x)\n"
        "    switch x\n"
        "      n when n > 10 =>\n"
        "        result = n * 2\n"
        "        result\n"
        "      _ => 0\n"
        "    end\n"
        "  end\n"
        "end\n"),
    ?assertEqual(30, Mod:run(15)),
    ?assertEqual(0, Mod:run(5)).

%% ── Rescue: multi-expression without do...end ──────────────────────────────

rescue_multiline_no_do_end_test() ->
    Mod = compile_and_load(
        "module NlRes1\n"
        "  def run()\n"
        "    try\n"
        "      1 / 0\n"
        "    rescue\n"
        "      _ =>\n"
        "        msg = \"caught\"\n"
        "        msg\n"
        "    end\n"
        "  end\n"
        "end\n"),
    ?assertEqual(<<"caught">>, Mod:run()).

%% ── Rescue: backward compat with do...end ───────────────────────────────────

rescue_do_end_backward_compat_test() ->
    Mod = compile_and_load(
        "module NlRes2\n"
        "  def run()\n"
        "    try\n"
        "      1 / 0\n"
        "    rescue\n"
        "      _ => do\n"
        "        msg = \"caught\"\n"
        "        msg\n"
        "      end\n"
        "    end\n"
        "  end\n"
        "end\n"),
    ?assertEqual(<<"caught">>, Mod:run()).

%% ── Newlines inside brackets suppressed ─────────────────────────────────────

newlines_in_brackets_suppressed_test() ->
    Mod = compile_and_load(
        "module NlBrack\n"
        "  def run()\n"
        "    Enum.map(\n"
        "      [1, 2, 3]\n"
        "    ) do |x|\n"
        "      x * 2\n"
        "    end\n"
        "  end\n"
        "end\n"),
    ?assertEqual([2, 4, 6], Mod:run()).

%% ── Filter strips newlines for normal code ──────────────────────────────────

filter_strips_newlines_test() ->
    {ok, Raw, _} = winn_lexer:string("module X\n  def run()\n    42\n  end\nend\n"),
    Filtered = winn_newline_filter:filter(Raw),
    NewlineCount = length([T || {newline, _} = T <- Filtered]),
    ?assertEqual(0, NewlineCount).

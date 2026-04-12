%% winn_private_fns_tests.erl
%% Tests for `private def` — module-private functions (#128).

-module(winn_private_fns_tests).
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

%% ── Parser ───────────────────────────────────────────────────────────────

private_def_parses_test() ->
    Source = "module Pp\n  private def helper(x)\n    x\n  end\nend\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, [{module, _, _, [{private_function, _, helper, _, _}]}]} =
        winn_parser:parse(Tokens),
    ok.

private_def_with_guard_parses_test() ->
    Source = "module Pp\n  private def positive(x) when x > 0\n    x\n  end\nend\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, [{module, _, _, [{private_function_g, _, positive, _, _, _}]}]} =
        winn_parser:parse(Tokens),
    ok.

%% ── Codegen / runtime ────────────────────────────────────────────────────

private_function_excluded_from_exports_test() ->
    Mod = compile_and_load(
        "module ExportFilter\n"
        "  def public_one()\n"
        "    1\n"
        "  end\n"
        "  private def helper(x)\n"
        "    x + 1\n"
        "  end\n"
        "end\n"),
    Exports = Mod:module_info(exports),
    ?assert(lists:member({public_one, 0}, Exports)),
    ?assertNot(lists:member({helper, 1}, Exports)).

private_function_callable_from_same_module_test() ->
    Mod = compile_and_load(
        "module SameMod\n"
        "  def double_it(x)\n"
        "    helper(x)\n"
        "  end\n"
        "  private def helper(x)\n"
        "    x * 2\n"
        "  end\n"
        "end\n"),
    ?assertEqual(10, Mod:double_it(5)).

private_function_external_call_undef_test() ->
    Mod = compile_and_load(
        "module ExtCall\n"
        "  def public_fn()\n"
        "    1\n"
        "  end\n"
        "  private def secret()\n"
        "    42\n"
        "  end\n"
        "end\n"),
    ?assertError(undef, Mod:secret()).

guarded_private_function_works_test() ->
    Mod = compile_and_load(
        "module GuardPriv\n"
        "  def call_it(n)\n"
        "    positive(n)\n"
        "  end\n"
        "  private def positive(x) when x > 0\n"
        "    x\n"
        "  end\n"
        "  private def positive(_x)\n"
        "    0\n"
        "  end\n"
        "end\n"),
    ?assertEqual(7, Mod:call_it(7)),
    ?assertEqual(0, Mod:call_it(-3)),
    Exports = Mod:module_info(exports),
    ?assertNot(lists:member({positive, 1}, Exports)).

%% ── Lint ─────────────────────────────────────────────────────────────────

unused_private_function_warning_test() ->
    Source =
        "module UnusedPriv\n"
        "  def main()\n"
        "    1\n"
        "  end\n"
        "  private def dead_code()\n"
        "    99\n"
        "  end\n"
        "end\n",
    {ok, Warnings} = winn_lint:check_string(Source),
    Matching = [W || {warning, _, unused_private_function, _} = W <- Warnings],
    ?assertEqual(1, length(Matching)).

used_private_function_no_warning_test() ->
    Source =
        "module UsedPriv\n"
        "  def main()\n"
        "    helper(1)\n"
        "  end\n"
        "  private def helper(x)\n"
        "    x + 1\n"
        "  end\n"
        "end\n",
    {ok, Warnings} = winn_lint:check_string(Source),
    Matching = [W || {warning, _, unused_private_function, _} = W <- Warnings],
    ?assertEqual([], Matching).

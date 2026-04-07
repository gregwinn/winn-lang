%% winn_lint_tests.erl — EUnit tests for winn lint.

-module(winn_lint_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Helpers ──────────────────────────────────────────────────────────────

lint(Source) ->
    {ok, Violations} = winn_lint:check_string(Source),
    Violations.

has_rule(Rule, Violations) ->
    lists:any(fun({_, _, R, _}) -> R =:= Rule end, Violations).

%% ── Clean code produces no warnings ────────────────────────────────────

clean_code_test() ->
    Source = "module Hello\n"
             "  def main()\n"
             "    IO.puts(\"Hello\")\n"
             "  end\n"
             "end\n",
    ?assertEqual([], lint(Source)).

%% ── function_name_convention ───────────────────────────────────────────

camel_case_function_test() ->
    Source = "module Foo\n"
             "  def myFunction()\n"
             "    42\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assert(has_rule(function_name_convention, Vs)).

snake_case_ok_test() ->
    Source = "module Foo\n"
             "  def my_function()\n"
             "    42\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(function_name_convention, Vs)).

predicate_name_ok_test() ->
    Source = "module Foo\n"
             "  def valid?(x)\n"
             "    x\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(function_name_convention, Vs)).

%% ── module_name_convention ─────────────────────────────────────────────

%% Note: the parser requires PascalCase module names, so we can't test
%% a truly lowercase module name at the AST level. The module_name_convention
%% rule catches names that start uppercase but aren't proper PascalCase.
%% The parser itself enforces the uppercase-first constraint.

pascal_case_module_ok_test() ->
    Source = "module MyApp\n"
             "  def bar()\n"
             "    42\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(module_name_convention, Vs)).

%% ── empty_function_body ────────────────────────────────────────────────

empty_body_test() ->
    Source = "module Foo\n"
             "  def noop()\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assert(has_rule(empty_function_body, Vs)).

nonempty_body_ok_test() ->
    Source = "module Foo\n"
             "  def something()\n"
             "    42\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(empty_function_body, Vs)).

%% ── redundant_boolean ──────────────────────────────────────────────────

redundant_true_test() ->
    Source = "module Foo\n"
             "  def check(x)\n"
             "    if x == true\n"
             "      1\n"
             "    else\n"
             "      0\n"
             "    end\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assert(has_rule(redundant_boolean, Vs)).

redundant_false_test() ->
    Source = "module Foo\n"
             "  def check(x)\n"
             "    if x == false\n"
             "      1\n"
             "    else\n"
             "      0\n"
             "    end\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assert(has_rule(redundant_boolean, Vs)).

normal_comparison_ok_test() ->
    Source = "module Foo\n"
             "  def check(x)\n"
             "    if x == 1\n"
             "      1\n"
             "    else\n"
             "      0\n"
             "    end\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(redundant_boolean, Vs)).

%% ── pipe_into_literal ──────────────────────────────────────────────────

pipe_into_integer_test() ->
    Source = "module Foo\n"
             "  def bar()\n"
             "    1 |> 2\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assert(has_rule(pipe_into_literal, Vs)).

pipe_into_function_ok_test() ->
    Source = "module Foo\n"
             "  def bar(x)\n"
             "    x |> IO.puts()\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(pipe_into_literal, Vs)).

%% ── single_pipe ────────────────────────────────────────────────────────

single_pipe_test() ->
    Source = "module Foo\n"
             "  def bar(x)\n"
             "    x |> IO.puts()\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assert(has_rule(single_pipe, Vs)).

chained_pipe_ok_test() ->
    Source = "module Foo\n"
             "  def bar(x)\n"
             "    x |> String.upcase() |> IO.puts()\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(single_pipe, Vs)).

%% ── unused_variable ────────────────────────────────────────────────────

unused_var_test() ->
    Source = "module Foo\n"
             "  def bar(x)\n"
             "    42\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assert(has_rule(unused_variable, Vs)).

used_var_ok_test() ->
    Source = "module Foo\n"
             "  def bar(x)\n"
             "    x\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(unused_variable, Vs)).

underscore_prefix_ok_test() ->
    Source = "module Foo\n"
             "  def bar(_x)\n"
             "    42\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(unused_variable, Vs)).

wildcard_ok_test() ->
    Source = "module Foo\n"
             "  def bar(_)\n"
             "    42\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(unused_variable, Vs)).

%% ── unused_import ──────────────────────────────────────────────────────

unused_import_test() ->
    Source = "module Foo\n"
             "  import SomeLib\n"
             "  def bar()\n"
             "    42\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assert(has_rule(unused_import, Vs)).

used_import_ok_test() ->
    Source = "module Foo\n"
             "  import IO\n"
             "  def bar()\n"
             "    IO.puts(\"hi\")\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assertNot(has_rule(unused_import, Vs)).

%% ── unused_alias ───────────────────────────────────────────────────────

unused_alias_test() ->
    Source = "module Foo\n"
             "  alias MyApp.Router\n"
             "  def bar()\n"
             "    42\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    ?assert(has_rule(unused_alias, Vs)).

%% ── Multiple violations in one file ────────────────────────────────────

multiple_violations_test() ->
    Source = "module Foo\n"
             "  def camelCase(unused_param)\n"
             "  end\n"
             "end\n",
    Vs = lint(Source),
    %% Should have function_name_convention + empty_function_body + unused_variable
    ?assert(length(Vs) >= 2).

%% ── Parse errors return error tuple ────────────────────────────────────

parse_error_test() ->
    Source = "module Foo\n  def end\nend\n",
    Result = winn_lint:check_string(Source),
    ?assertMatch({error, _}, Result).

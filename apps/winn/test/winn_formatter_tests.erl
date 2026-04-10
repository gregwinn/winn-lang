%% winn_formatter_tests.erl — EUnit tests for winn fmt.

-module(winn_formatter_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Helpers ──────────────────────────────────────────────────────────────

fmt(Source) ->
    {ok, Result} = winn_formatter:format_string(Source),
    Result.

%% ── Basic formatting ────────────────────────────────────────────────────

hello_world_test() ->
    Source = "module Hello\n  def main()\n    IO.puts(\"Hello, World!\")\n  end\nend\n",
    ?assertEqual(Source, fmt(Source)).

trailing_newline_test() ->
    Source = "module Foo\n  def bar()\n    42\n  end\nend",
    Result = fmt(Source),
    ?assertEqual($\n, lists:last(Result)).

%% ── Indentation normalization ───────────────────────────────────────────

fix_indent_test() ->
    Bad = "module Foo\ndef bar()\n1\nend\nend\n",
    Expected = "module Foo\n  def bar()\n    1\n  end\nend\n",
    ?assertEqual(Expected, fmt(Bad)).

%% ── Blank lines between functions ───────────────────────────────────────

blank_lines_between_functions_test() ->
    Source = "module Foo\ndef bar()\n1\nend\ndef baz()\n2\nend\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "end\n\n  def baz") =/= nomatch).

%% ── Operator spacing ────────────────────────────────────────────────────

operator_spacing_test() ->
    Source = "module Foo\n  def bar()\n    1 + 2\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "1 + 2") =/= nomatch).

comparison_operators_test() ->
    Source = "module Foo\n  def bar(x)\n    x == 1\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "x == 1") =/= nomatch).

string_concat_test() ->
    Source = "module Foo\n  def bar()\n    \"a\" <> \"b\"\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "\"a\" <> \"b\"") =/= nomatch).

%% ── Pipe chain alignment ────────────────────────────────────────────────

pipe_chain_test() ->
    Source = "module Foo\n  def bar()\n    [1, 2, 3]\n      |> Enum.map() do |x| x * 2 end\n      |> IO.puts()\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "      |> Enum.map") =/= nomatch),
    ?assert(string:find(Result, "      |> IO.puts") =/= nomatch).

%% ── Idempotency ─────────────────────────────────────────────────────────

idempotent_simple_test() ->
    Source = "module Foo\n  def bar()\n    42\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

idempotent_complex_test() ->
    Source = "module Svc\n  def fetch(id)\n    try\n      match HTTP.get(id)\n        ok r => {:ok, r}\n        err e => {:error, e}\n      end\n    rescue\n      _ => {:error, :fail}\n    end\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

%% ── Comment preservation ────────────────────────────────────────────────

line_comment_test() ->
    Source = "module Foo\n  # A helper function\n  def bar()\n    42\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "# A helper function") =/= nomatch).

multiple_comments_test() ->
    Source = "module Foo\n  # First\n  def bar()\n    42\n  end\n\n  # Second\n  def baz()\n    99\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "# First") =/= nomatch),
    ?assert(string:find(Result, "# Second") =/= nomatch).

%% ── Guard functions ─────────────────────────────────────────────────────

guard_function_test() ->
    Source = "module Foo\n  def bar(n) when n > 0\n    n\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "def bar(n) when n > 0") =/= nomatch).

%% ── Pattern matching ────────────────────────────────────────────────────

pattern_params_test() ->
    Source = "module Foo\n  def bar(0)\n    :zero\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "def bar(0)") =/= nomatch).

tuple_pattern_test() ->
    Source = "module Foo\n  def bar({:ok, val})\n    val\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "def bar({:ok, val})") =/= nomatch).

%% ── If/else ─────────────────────────────────────────────────────────────

if_else_test() ->
    Source = "module Foo\n  def bar(x)\n    if x > 0\n      :pos\n    else\n      :neg\n    end\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

if_no_else_test() ->
    Source = "module Foo\n  def bar(x)\n    if x > 0\n      :pos\n    end\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

%% ── Switch ──────────────────────────────────────────────────────────────

switch_test() ->
    Source = "module Foo\n  def bar(x)\n    switch x\n      0 => :zero\n      1 => :one\n      _ => :other\n    end\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

%% ── Match block ─────────────────────────────────────────────────────────

match_block_test() ->
    Source = "module Foo\n  def bar()\n    match get()\n      ok val => val\n      err _ => nil\n    end\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

%% ── Try/rescue ──────────────────────────────────────────────────────────

try_rescue_test() ->
    Source = "module Foo\n  def bar()\n    try\n      risky()\n    rescue\n      _ => :error\n    end\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

%% ── For comprehension ───────────────────────────────────────────────────

for_test() ->
    Source = "module Foo\n  def bar()\n    for x in [1, 2, 3] do\n      x * 2\n    end\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

%% ── Anonymous function ──────────────────────────────────────────────────

lambda_test() ->
    Source = "module Foo\n  def bar()\n    fn(x) => x + 1 end\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

%% ── Block call ──────────────────────────────────────────────────────────

block_call_single_test() ->
    Source = "module Foo\n  def bar()\n    Enum.map([1, 2]) do |x| x * 2 end\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

block_call_multi_test() ->
    Source = "module Foo\n  def bar()\n    Enum.each([1, 2]) do |x|\n      IO.puts(x)\n    end\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2).

%% ── Literals ────────────────────────────────────────────────────────────

map_literal_test() ->
    Source = "module Foo\n  def bar()\n    %{name: \"Greg\", age: 30}\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "%{name: \"Greg\", age: 30}") =/= nomatch).

list_literal_test() ->
    Source = "module Foo\n  def bar()\n    [1, 2, 3]\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "[1, 2, 3]") =/= nomatch).

tuple_literal_test() ->
    Source = "module Foo\n  def bar()\n    {:ok, 42}\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "{:ok, 42}") =/= nomatch).

range_test() ->
    Source = "module Foo\n  def bar()\n    1..10\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "1..10") =/= nomatch).

nil_test() ->
    Source = "module Foo\n  def bar()\n    nil\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "nil") =/= nomatch).

boolean_test() ->
    Source = "module Foo\n  def bar()\n    true\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "true") =/= nomatch).

%% ── Interpolated string ─────────────────────────────────────────────────

interp_string_test() ->
    Source = "module Foo\n  def bar(name)\n    \"hello #{name}\"\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "\"hello #{name}\"") =/= nomatch).

%% ── Assignment ──────────────────────────────────────────────────────────

assign_test() ->
    Source = "module Foo\n  def bar()\n    x = 42\n    x\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "x = 42") =/= nomatch).

%% ── Directives ──────────────────────────────────────────────────────────

use_directive_test() ->
    Source = "module Foo\n  use Winn.Schema\n\n  def bar()\n    42\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "use Winn.Schema") =/= nomatch).

import_directive_test() ->
    Source = "module Foo\n  import HTTP\n\n  def bar()\n    42\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "import HTTP") =/= nomatch).

%% ── Agent ───────────────────────────────────────────────────────────────

agent_test() ->
    Source = "agent Counter\n  state count = 0\n\n  def value()\n    @count\n  end\n\n  async def increment()\n    @count = @count + 1\n  end\nend\n",
    R1 = fmt(Source),
    R2 = fmt(R1),
    ?assertEqual(R1, R2),
    ?assert(string:find(R1, "agent Counter") =/= nomatch),
    ?assert(string:find(R1, "state count = 0") =/= nomatch),
    ?assert(string:find(R1, "@count") =/= nomatch),
    ?assert(string:find(R1, "async def increment") =/= nomatch).

%% ── Struct ──────────────────────────────────────────────────────────────

struct_test() ->
    Source = "module Foo\n  struct [:name, :age]\n\n  def bar()\n    42\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "struct [:name, :age]") =/= nomatch).

%% ── Default params ──────────────────────────────────────────────────────

default_param_test() ->
    Source = "module Foo\n  def bar(x = 10)\n    x\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "def bar(x = 10)") =/= nomatch).

%% ── Unary operators ─────────────────────────────────────────────────────

unary_minus_test() ->
    Source = "module Foo\n  def bar()\n    -1\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "-1") =/= nomatch).

unary_not_test() ->
    Source = "module Foo\n  def bar(x)\n    not x\n  end\nend\n",
    Result = fmt(Source),
    ?assert(string:find(Result, "not x") =/= nomatch).

%% ── Check mode ──────────────────────────────────────────────────────────

check_formatted_test() ->
    Source = "module Foo\n  def bar()\n    42\n  end\nend\n",
    TmpFile = "/tmp/winn_fmt_test_ok.winn",
    ok = file:write_file(TmpFile, Source),
    ?assertEqual(ok, winn_formatter:check_file(TmpFile)),
    file:delete(TmpFile).

check_unformatted_test() ->
    Source = "module Foo\ndef bar()\n42\nend\nend\n",
    TmpFile = "/tmp/winn_fmt_test_bad.winn",
    ok = file:write_file(TmpFile, Source),
    ?assertMatch({changed, _}, winn_formatter:check_file(TmpFile)),
    file:delete(TmpFile).

%% ── Example file round-trips ────────────────────────────────────────────

example_hello_idempotent_test() ->
    {ok, R1} = winn_formatter:format_file("examples/hello.winn"),
    {ok, R2} = winn_formatter:format_string(R1),
    ?assertEqual(R1, R2).

example_fibonacci_idempotent_test() ->
    {ok, R1} = winn_formatter:format_file("examples/fibonacci.winn"),
    {ok, R2} = winn_formatter:format_string(R1),
    ?assertEqual(R1, R2).

example_web_service_idempotent_test() ->
    {ok, R1} = winn_formatter:format_file("examples/web_service.winn"),
    {ok, R2} = winn_formatter:format_string(R1),
    ?assertEqual(R1, R2).

example_pipeline_idempotent_test() ->
    {ok, R1} = winn_formatter:format_file("examples/pipeline.winn"),
    {ok, R2} = winn_formatter:format_string(R1),
    ?assertEqual(R1, R2).

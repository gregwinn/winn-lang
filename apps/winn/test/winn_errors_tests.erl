%% winn_errors_tests.erl — MI5: Error formatting tests.

-module(winn_errors_tests).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    winn_errors:set_color(false).

%% ── Lexer error formatting ──────────────────────────────────────────────

lex_error_test() ->
    setup(),
    Source = "module Test\n  def foo()\n    @bad\n  end\nend\n",
    Result = winn_errors:format(
        {lex_error, "test.winn", 3, "illegal characters \"@\""},
        Source, "test.winn"),
    ?assert(is_binary(Result)),
    %% Contains the title
    ?assertNotEqual(nomatch, binary:match(Result, <<"Illegal Character">>)),
    %% Contains the file name
    ?assertNotEqual(nomatch, binary:match(Result, <<"test.winn">>)),
    %% Contains the source line
    ?assertNotEqual(nomatch, binary:match(Result, <<"@bad">>)).

%% ── Parser error formatting ─────────────────────────────────────────────

parse_error_test() ->
    setup(),
    Source = "module Test\n  def foo()\n  end\nend\n",
    Result = winn_errors:format(
        {parse_error, "test.winn", 3, ["syntax error before: ", "'end'"]},
        Source, "test.winn"),
    ?assert(is_binary(Result)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"Syntax Error">>)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"end">>)).

parse_error_hint_test() ->
    setup(),
    Source = "module Test\n  end\n",
    Result = winn_errors:format(
        {parse_error, "test.winn", 2, ["syntax error before: ", "'end'"]},
        Source, "test.winn"),
    %% Should include hint for 'end' token
    ?assertNotEqual(nomatch, binary:match(Result, <<"Hint">>)).

%% ── Undefined variable formatting ───────────────────────────────────────

unbound_var_test() ->
    setup(),
    Source = "module Test\n  def foo()\n    x\n  end\nend\n",
    Errors = [{"test", [{none, core_lint, {unbound_var, 'X', {foo, 0}}}]}],
    Result = winn_errors:format({compile_failed, Errors}, Source, "test.winn"),
    ?assert(is_binary(Result)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"Undefined Variable">>)),
    %% Should show lowercase Winn var name, not Core Erlang uppercase
    ?assertNotEqual(nomatch, binary:match(Result, <<"'x'">>)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"foo/0">>)).

%% ── Transform error formatting ──────────────────────────────────────────

transform_error_test() ->
    setup(),
    Source = "module Test\n  def foo()\n    bad\n  end\nend\n",
    Result = winn_errors:format(
        {transform_error, "test.winn", 3,
         <<"Unsupported Pipe Target">>,
         <<"The right side of |> must be a function call.">>},
        Source, "test.winn"),
    ?assert(is_binary(Result)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"Pipe Target">>)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"function call">>)).

%% ── File error formatting ───────────────────────────────────────────────

file_error_test() ->
    setup(),
    Result = winn_errors:format(
        {file_read, "missing.winn", enoent},
        "", "missing.winn"),
    ?assert(is_binary(Result)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"File Error">>)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"missing.winn">>)).

%% ── No line info (graceful handling) ────────────────────────────────────

no_line_test() ->
    setup(),
    Result = winn_errors:format(
        {codegen_error, "test.winn", none,
         <<"Code Generation Error">>,
         <<"Something went wrong.">>},
        "module Test\nend\n", "test.winn"),
    ?assert(is_binary(Result)),
    %% Should not crash, just omit source context
    ?assertNotEqual(nomatch, binary:match(Result, <<"Code Generation">>)).

%% ── Integration: compile_string returns error ───────────────────────────

compile_string_lex_error_test() ->
    setup(),
    %% compile_string should return {error, _} for bad source.
    Result = winn:compile_string("module Test\n  @bad\nend\n", "test.winn", "/tmp"),
    ?assertMatch({error, _}, Result).

compile_string_parse_error_test() ->
    setup(),
    Result = winn:compile_string("module Test\n  end end\nend\n", "test.winn", "/tmp"),
    ?assertMatch({error, _}, Result).

%% ── Color toggle test ───────────────────────────────────────────────────

color_disabled_test() ->
    winn_errors:set_color(false),
    Result = winn_errors:format(
        {lex_error, "t.winn", 1, "bad"},
        "bad\n", "t.winn"),
    %% Should have no ANSI escape codes
    ?assertEqual(nomatch, binary:match(Result, <<"\e[">>)).

color_enabled_test() ->
    winn_errors:set_color(true),
    Result = winn_errors:format(
        {lex_error, "t.winn", 1, "bad"},
        "bad\n", "t.winn"),
    %% Should contain ANSI escape codes
    ?assertNotEqual(nomatch, binary:match(Result, <<"\e[">>)),
    %% Reset for other tests
    winn_errors:set_color(false).

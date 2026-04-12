-module(winn_lsp_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test the diagnostic compilation function directly.
%% We can't easily test the full stdio LSP loop, but we can test
%% the core logic that converts source to diagnostics.

%% ── Valid source produces no diagnostics ──────────────────────────────────

valid_source_test() ->
    Source = "module Valid\n  def main()\n    IO.puts(\"hello\")\n  end\nend\n",
    Diags = winn_lsp:compile_for_diagnostics(Source),
    ?assertEqual([], Diags).

%% ── Lex error produces diagnostic ────────────────────────────────────────

lex_error_test() ->
    Source = "module Bad\n  def main()\n    `invalid\n  end\nend\n",
    Diags = winn_lsp:compile_for_diagnostics(Source),
    ?assertEqual(1, length(Diags)),
    [D] = Diags,
    ?assertEqual(1, maps:get(<<"severity">>, D)),
    ?assertEqual(<<"winn">>, maps:get(<<"source">>, D)).

%% ── Parse error produces diagnostic ──────────────────────────────────────

parse_error_test() ->
    Source = "module Bad\n  def main()\n    end end\n  end\nend\n",
    Diags = winn_lsp:compile_for_diagnostics(Source),
    ?assert(length(Diags) >= 1),
    [D | _] = Diags,
    ?assertEqual(1, maps:get(<<"severity">>, D)).

%% ── Diagnostic has correct range structure ───────────────────────────────

diagnostic_range_test() ->
    Source = "module Bad\n  def main()\n    end end\n  end\nend\n",
    [D | _] = winn_lsp:compile_for_diagnostics(Source),
    Range = maps:get(<<"range">>, D),
    Start = maps:get(<<"start">>, Range),
    ?assert(is_map(Start)),
    ?assert(maps:is_key(<<"line">>, Start)),
    ?assert(maps:is_key(<<"character">>, Start)).

%% ── Multiple errors ──────────────────────────────────────────────────────

empty_source_test() ->
    Diags = winn_lsp:compile_for_diagnostics(""),
    ?assertEqual([], Diags).

%% ── Lint warnings surface as diagnostics ─────────────────────────────────

lint_warning_test() ->
    %% camelCase function name trips function_name_convention
    Source = "module Lintme\n  def badName()\n    IO.puts(\"hi\")\n  end\nend\n",
    Diags = winn_lsp:compile_for_diagnostics(Source),
    Warnings = [D || D <- Diags, maps:get(<<"severity">>, D) =:= 2],
    ?assert(length(Warnings) >= 1),
    [W | _] = Warnings,
    ?assertEqual(<<"function_name_convention">>, maps:get(<<"code">>, W)),
    ?assertEqual(<<"winn">>, maps:get(<<"source">>, W)).

lint_warning_cleared_when_fixed_test() ->
    Source = "module Lintme\n  def good_name()\n    IO.puts(\"hi\")\n  end\nend\n",
    Diags = winn_lsp:compile_for_diagnostics(Source),
    Warnings = [D || D <- Diags,
                     maps:get(<<"severity">>, D) =:= 2,
                     maps:get(<<"code">>, D, undefined) =:= <<"function_name_convention">>],
    ?assertEqual([], Warnings).

%% ── Document symbols ─────────────────────────────────────────────────────

document_symbols_module_test() ->
    Source = "module Greeter\n  import IO\n  alias Foo.Bar\n  def greet(name)\n    IO.puts(name)\n  end\n  def main()\n    greet(\"world\")\n  end\nend\n",
    [Mod] = winn_lsp:document_symbols(Source),
    ?assertEqual(<<"Greeter">>, maps:get(<<"name">>, Mod)),
    ?assertEqual(2, maps:get(<<"kind">>, Mod)),  %% Module
    Children = maps:get(<<"children">>, Mod),
    Names = [maps:get(<<"name">>, C) || C <- Children],
    ?assert(lists:member(<<"IO">>, Names)),
    ?assert(lists:member(<<"Foo.Bar">>, Names)),
    ?assert(lists:member(<<"greet/1">>, Names)),
    ?assert(lists:member(<<"main/0">>, Names)).

document_symbols_function_kind_test() ->
    Source = "module M\n  def f()\n    1\n  end\nend\n",
    [Mod] = winn_lsp:document_symbols(Source),
    [Fn] = [C || C <- maps:get(<<"children">>, Mod),
                 maps:get(<<"name">>, C) =:= <<"f/0">>],
    ?assertEqual(12, maps:get(<<"kind">>, Fn)).  %% Function

document_symbols_agent_kind_test() ->
    Source = "agent Counter\n  def value()\n    0\n  end\nend\n",
    [Sym] = winn_lsp:document_symbols(Source),
    ?assertEqual(<<"Counter">>, maps:get(<<"name">>, Sym)),
    ?assertEqual(5, maps:get(<<"kind">>, Sym)),  %% Class
    [Fn] = maps:get(<<"children">>, Sym),
    ?assertEqual(<<"value/0">>, maps:get(<<"name">>, Fn)).

document_symbols_parse_error_returns_empty_test() ->
    ?assertEqual([], winn_lsp:document_symbols("module Bad\n  def end end\nend\n")).

%% ── Hover ────────────────────────────────────────────────────────────────

%% Source layout (0-indexed lines, 1-indexed in source):
%%   line 0 (1): module M
%%   line 1 (2):   def greet(name)
%%   line 2 (3):     name
%%   line 3 (4):   end
%%   line 4 (5):   def main()
%%   line 5 (6):     greet("hi")
%%   line 6 (7):   end
%%   line 7 (8): end
hover_function_signature_test() ->
    Source = "module M\n  def greet(name)\n    name\n  end\n  def main()\n    greet(\"hi\")\n  end\nend\n",
    %% Hover on `greet` at line 5 (call site), char ~4 (the 'g' of greet)
    Hover = winn_lsp:hover_at(Source, 5, 5),
    ?assertNotEqual(null, Hover),
    Contents = maps:get(<<"contents">>, Hover),
    Value = maps:get(<<"value">>, Contents),
    ?assert(binary:match(Value, <<"greet/1">>) =/= nomatch),
    ?assert(binary:match(Value, <<"def greet(name)">>) =/= nomatch).

hover_with_doc_comment_test() ->
    Source =
        "module M\n"
        "  # Greets the user by name\n"
        "  def greet(name)\n"
        "    name\n"
        "  end\nend\n",
    %% Cursor on `greet` in `def greet(name)` — line index 2, char 6
    Hover = winn_lsp:hover_at(Source, 2, 6),
    ?assertNotEqual(null, Hover),
    Value = maps:get(<<"value">>, maps:get(<<"contents">>, Hover)),
    ?assert(binary:match(Value, <<"Greets the user by name">>) =/= nomatch).

hover_returns_null_for_whitespace_test() ->
    Source = "module M\n  def f()\n    1\n  end\nend\n",
    %% Empty area at end of line
    ?assertEqual(null, winn_lsp:hover_at(Source, 0, 0)).

hover_returns_null_for_unknown_identifier_test() ->
    Source = "module M\n  def f()\n    1\n  end\nend\n",
    %% Hover on `M` (module name) — not a function we track
    ?assertEqual(null, winn_lsp:hover_at(Source, 0, 7)).

%% Lint should not be invoked when parsing fails (no spurious lint errors).
lint_skipped_on_parse_error_test() ->
    Source = "module Bad\n  def main()\n    end end\n  end\nend\n",
    Diags = winn_lsp:compile_for_diagnostics(Source),
    %% All diagnostics should be parse errors (severity 1, no code field)
    ?assert(lists:all(fun(D) ->
        maps:get(<<"severity">>, D) =:= 1
            andalso not maps:is_key(<<"code">>, D)
    end, Diags)).

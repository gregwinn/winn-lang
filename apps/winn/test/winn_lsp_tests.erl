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

%% Lint should not be invoked when parsing fails (no spurious lint errors).
lint_skipped_on_parse_error_test() ->
    Source = "module Bad\n  def main()\n    end end\n  end\nend\n",
    Diags = winn_lsp:compile_for_diagnostics(Source),
    %% All diagnostics should be parse errors (severity 1, no code field)
    ?assert(lists:all(fun(D) ->
        maps:get(<<"severity">>, D) =:= 1
            andalso not maps:is_key(<<"code">>, D)
    end, Diags)).

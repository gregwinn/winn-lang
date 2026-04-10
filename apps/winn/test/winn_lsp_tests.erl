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

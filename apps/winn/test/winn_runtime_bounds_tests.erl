%% winn_runtime_bounds_tests.erl
%% Tests for runtime bounds checking and safe defaults (#58).

-module(winn_runtime_bounds_tests).
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

%% ── List.first / List.last on [] return nil (was :not_found) ──────────────

list_first_empty_test() ->
    ?assertEqual(nil, winn_runtime:'list.first'([])).

list_first_populated_test() ->
    ?assertEqual(1, winn_runtime:'list.first'([1,2,3])).

list_last_empty_test() ->
    ?assertEqual(nil, winn_runtime:'list.last'([])).

list_last_populated_test() ->
    ?assertEqual(3, winn_runtime:'list.last'([1,2,3])).

%% ── Map.get: missing key → nil, non-map → error tuple ─────────────────────

map_get_missing_key_test() ->
    ?assertEqual(nil, winn_runtime:'map.get'(absent, #{a => 1})).

map_get_existing_key_test() ->
    ?assertEqual(42, winn_runtime:'map.get'(a, #{a => 42})).

map_get_non_map_test() ->
    ?assertEqual({error, not_a_map}, winn_runtime:'map.get'(key, [not_a_map])),
    ?assertEqual({error, not_a_map}, winn_runtime:'map.get'(key, <<"binary">>)),
    ?assertEqual({error, not_a_map}, winn_runtime:'map.get'(key, nil)).

%% ── String.slice: out-of-range → empty, never crashes ─────────────────────

string_slice_past_end_test() ->
    ?assertEqual(<<>>, winn_runtime:'string.slice'(<<"hello">>, 10, 5)).

string_slice_negative_start_test() ->
    ?assertEqual(<<"hello">>, winn_runtime:'string.slice'(<<"hello">>, -3, 5)).

string_slice_negative_length_test() ->
    ?assertEqual(<<>>, winn_runtime:'string.slice'(<<"hello">>, 0, -3)).

string_slice_oversize_length_test() ->
    ?assertEqual(<<"llo">>, winn_runtime:'string.slice'(<<"hello">>, 2, 100)).

string_slice_non_binary_test() ->
    ?assertEqual(<<>>, winn_runtime:'string.slice'(nil, 0, 5)),
    ?assertEqual(<<>>, winn_runtime:'string.slice'(42, 0, 5)).

%% ── Enum.reduce on [] already returns the accumulator (no change needed) ──

enum_reduce_empty_test() ->
    ?assertEqual(0, winn_runtime:'enum.reduce'([], 0, fun(X, Acc) -> X + Acc end)).

%% ── Map field access (user.name) returns nil on missing key ───────────────

field_access_missing_test() ->
    Mod = compile_and_load(
        "module FieldMissing\n"
        "  def run()\n"
        "    u = %{name: \"alice\"}\n"
        "    u.email\n"
        "  end\n"
        "end\n"),
    ?assertEqual(nil, Mod:run()).

field_access_present_test() ->
    Mod = compile_and_load(
        "module FieldPresent\n"
        "  def run()\n"
        "    u = %{name: \"alice\", age: 30}\n"
        "    u.name\n"
        "  end\n"
        "end\n"),
    ?assertEqual(<<"alice">>, Mod:run()).

%% ── End-to-end through Winn surface for the rest ──────────────────────────

list_first_from_winn_test() ->
    Mod = compile_and_load(
        "module ListFirstEmpty\n"
        "  def run()\n"
        "    List.first([])\n"
        "  end\n"
        "end\n"),
    ?assertEqual(nil, Mod:run()).

map_get_from_winn_test() ->
    Mod = compile_and_load(
        "module MapGetMiss\n"
        "  def run()\n"
        "    Map.get(:absent, %{a: 1})\n"
        "  end\n"
        "end\n"),
    ?assertEqual(nil, Mod:run()).

string_slice_from_winn_test() ->
    Mod = compile_and_load(
        "module SliceSafe\n"
        "  def run()\n"
        "    String.slice(\"hello\", 100, 5)\n"
        "  end\n"
        "end\n"),
    ?assertEqual(<<>>, Mod:run()).

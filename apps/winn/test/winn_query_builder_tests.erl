%% winn_query_builder_tests.erl
%% Tests for extended query builder (#43).

-module(winn_query_builder_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Repo exports new query functions ────────────────────────────────────────

exports_order_by_test() ->
    Exports = winn_repo:module_info(exports),
    ?assert(lists:member({'query.order_by', 3}, Exports)).

exports_select_test() ->
    Exports = winn_repo:module_info(exports),
    ?assert(lists:member({'query.select', 2}, Exports)).

exports_query_count_test() ->
    Exports = winn_repo:module_info(exports),
    ?assert(lists:member({'query.count', 1}, Exports)).

exports_aggregate_test() ->
    Exports = winn_repo:module_info(exports),
    ?assert(lists:member({aggregate, 3}, Exports)).

%% ── Query map building ─────────────────────────────────────────────────────

query_new_test() ->
    Q = winn_repo:'query.new'(fake_mod),
    ?assertEqual(fake_mod, maps:get(schema, Q)),
    ?assertEqual([], maps:get(wheres, Q)),
    ?assertEqual(all, maps:get(limit, Q)),
    ?assertEqual(none, maps:get(order_by, Q)),
    ?assertEqual(all, maps:get(select, Q)).

query_where_test() ->
    Q = winn_repo:'query.new'(fake_mod),
    Q2 = winn_repo:'query.where'(Q, name, <<"Alice">>),
    ?assertEqual([{name, <<"Alice">>}], maps:get(wheres, Q2)).

query_order_by_test() ->
    Q = winn_repo:'query.new'(fake_mod),
    Q2 = winn_repo:'query.order_by'(Q, created_at, desc),
    ?assertEqual({created_at, desc}, maps:get(order_by, Q2)).

query_select_test() ->
    Q = winn_repo:'query.new'(fake_mod),
    Q2 = winn_repo:'query.select'(Q, [name, email]),
    ?assertEqual([name, email], maps:get(select, Q2)).

query_limit_test() ->
    Q = winn_repo:'query.new'(fake_mod),
    Q2 = winn_repo:'query.limit'(Q, 10),
    ?assertEqual(10, maps:get(limit, Q2)).

%% ── Chaining ────────────────────────────────────────────────────────────────

query_chain_test() ->
    Q = winn_repo:'query.new'(fake_mod),
    Q2 = winn_repo:'query.where'(Q, active, true),
    Q3 = winn_repo:'query.order_by'(Q2, name, asc),
    Q4 = winn_repo:'query.limit'(Q3, 20),
    Q5 = winn_repo:'query.select'(Q4, [name, email]),
    ?assertEqual([{active, true}], maps:get(wheres, Q5)),
    ?assertEqual({name, asc}, maps:get(order_by, Q5)),
    ?assertEqual(20, maps:get(limit, Q5)),
    ?assertEqual([name, email], maps:get(select, Q5)).

%% ── build_where helper ──────────────────────────────────────────────────────

build_where_empty_test() ->
    {SQL, Vals} = winn_repo:build_where([]),
    ?assertEqual(<<>>, SQL),
    ?assertEqual([], Vals).

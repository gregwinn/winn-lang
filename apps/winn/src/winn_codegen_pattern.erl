%% winn_codegen_pattern.erl
%% Pattern and parameter generation for Core Erlang.
%%
%% Handles gen_pattern/1 (case clause patterns) and gen_param/1
%% (function parameters). Extracted from winn_codegen.erl.

-module(winn_codegen_pattern).
-export([gen_pattern/1, gen_param/1]).

-import(winn_codegen_resolve, [var_atom/1]).

%% ── Function parameters ──────────────────────────────────────────────────
%% After Phase 2 transform, params are always simple variables.

gen_param({var, _, Name})        -> cerl:c_var(var_atom(Name));
gen_param({pat_wildcard, _})     -> cerl:c_var('_');
gen_param({pat_var, _, Name})    -> cerl:c_var(var_atom(Name)).  %% defensive

%% ── Patterns ─────────────────────────────────────────────────────────────
%%
%% gen_pattern/1 produces cerl pattern nodes (not expressions).
%% These can only appear in case clause pattern positions.

gen_pattern({var, _Line, Name}) ->
    cerl:c_var(var_atom(Name));

gen_pattern({pat_var, _Line, Name}) ->
    cerl:c_var(var_atom(Name));

gen_pattern({pat_wildcard, _Line}) ->
    cerl:c_var('_');

gen_pattern({pat_atom, _Line, Value}) ->
    cerl:c_atom(Value);

gen_pattern({pat_integer, _Line, Value}) ->
    cerl:c_int(Value);

gen_pattern({pat_tuple, _Line, Elements}) ->
    cerl:c_tuple([gen_pattern(E) || E <- Elements]);

gen_pattern({pat_list, _Line, [], nil}) ->
    cerl:c_nil();
gen_pattern({pat_list, _Line, [], TailPat}) ->
    gen_pattern(TailPat);
gen_pattern({pat_list, _Line, [H | T], Tail}) ->
    cerl:c_cons(gen_pattern(H), gen_pattern({pat_list, 0, T, Tail}));

gen_pattern(Unknown) ->
    error({unsupported_pattern_node, Unknown}).

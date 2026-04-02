%% winn_codegen.erl
%% Translates the lowered Winn AST into Core Erlang using the cerl module.
%%
%% Phase 1: modules, functions, calls, literals, pipes (desugared by transform).
%% Phase 2: pattern matching, case expressions, multi-clause functions.

-module(winn_codegen).
-export([gen/1]).

%% Generate Core Erlang for a list of top-level forms.
gen(Forms) ->
    [gen_module(F) || F <- Forms].

%% ── Module ─────────────────────────────────────────────────────────────────

gen_module({module, _Line, Name, Body}) ->
    ModName   = cerl:c_atom(winn_module_atom(Name)),
    Functions = [F || F <- Body, element(1, F) =:= function],
    BehavAttrs = [B || B <- Body, element(1, B) =:= behaviour_attr],

    %% Every def is public in Phase 1/2.
    Exports = [cerl:c_var({fn_atom(FName), length(Params)})
               || {function, _, FName, Params, _} <- Functions],

    Attrs = [{cerl:c_atom(behaviour),
              cerl:abstract([BehName])}
             || {behaviour_attr, _, BehName} <- BehavAttrs],

    Defs = [gen_function(F) || F <- Functions],

    %% Add module_info/0 and module_info/1 (not auto-generated for from_core).
    MI0Var = cerl:c_var({module_info, 0}),
    MI0Fun = cerl:c_fun([],
        cerl:c_call(cerl:c_atom(erlang), cerl:c_atom(get_module_info),
                    [ModName])),
    MI1Arg = cerl:c_var('X'),
    MI1Var = cerl:c_var({module_info, 1}),
    MI1Fun = cerl:c_fun([MI1Arg],
        cerl:c_call(cerl:c_atom(erlang), cerl:c_atom(get_module_info),
                    [ModName, MI1Arg])),

    AllExports = Exports ++ [MI0Var, MI1Var],
    AllDefs    = Defs ++ [{MI0Var, MI0Fun}, {MI1Var, MI1Fun}],

    cerl:c_module(ModName, AllExports, Attrs, AllDefs).

%% ── Function ───────────────────────────────────────────────────────────────

gen_function({function, _Line, Name, Params, Body}) ->
    FVar      = cerl:c_var({fn_atom(Name), length(Params)}),
    ParamVars = [gen_param(P) || P <- Params],
    BodyExpr  = gen_body(Body),
    {FVar, cerl:c_fun(ParamVars, BodyExpr)}.

%% Generate a Core Erlang variable for a function parameter.
%% After Phase 2 transform, params are always simple variables.
gen_param({var, _, Name})        -> cerl:c_var(var_atom(Name));
gen_param({pat_wildcard, _})     -> cerl:c_var('_');
gen_param({pat_var, _, Name})    -> cerl:c_var(var_atom(Name)).  %% defensive

%% Sequence of expressions; last one is the return value.
%% Assignments scope over the rest of the body via let bindings.
gen_body([]) ->
    cerl:c_atom(nil);
gen_body([Single]) ->
    gen_expr(Single);
gen_body([{assign, _Line, {var, _, VName}, Expr} | Rest]) ->
    Var = cerl:c_var(var_atom(VName)),
    cerl:c_let([Var], gen_expr(Expr), gen_body(Rest));
gen_body([{pat_assign_case, _Line, Pat, CaseExpr} | Rest]) ->
    %% Pattern assignment: bind the matched value, then continue with
    %% the pattern variables in scope via the case clause.
    %% We generate: case Expr of Pat -> <rest of body> end
    {case_expr, _, Scrutinee, [{case_clause, CLine, Pats, Guard, _Body}]} = CaseExpr,
    CerlScrutinee = gen_expr(Scrutinee),
    CerlPats = [gen_pattern(P) || P <- Pats],
    CerlGuard = case Guard of
        none -> cerl:c_atom(true);
        _    -> gen_expr(Guard)
    end,
    CerlBody = gen_body(Rest),
    Clause = cerl:c_clause(CerlPats, CerlGuard, CerlBody),
    cerl:c_case(CerlScrutinee, [Clause]);
gen_body([First | Rest]) ->
    cerl:c_seq(gen_expr(First), gen_body(Rest)).

%% ── Expressions ────────────────────────────────────────────────────────────

%% Case expression (from match block or multi-clause function).
gen_expr({case_expr, _Line, Scrutinee, Clauses}) ->
    CerlScrutinee = gen_expr(Scrutinee),
    CerlClauses   = [gen_case_clause(C) || C <- Clauses],
    cerl:c_case(CerlScrutinee, CerlClauses);

%% Local call — check for built-in runtime functions first.
gen_expr({call, _Line, Fun, Args}) when
        Fun =:= to_string; Fun =:= to_integer;
        Fun =:= to_float;  Fun =:= to_atom;
        Fun =:= inspect ->
    CArgs = [gen_expr(A) || A <- Args],
    cerl:c_call(cerl:c_atom(winn_runtime), cerl:c_atom(Fun), CArgs);
%% Test assertion builtins — routed to winn_test module.
gen_expr({call, _Line, Fun, Args}) when
        Fun =:= assert; Fun =:= assert_equal ->
    CArgs = [gen_expr(A) || A <- Args],
    cerl:c_call(cerl:c_atom(winn_test), cerl:c_atom(Fun), CArgs);
gen_expr({call, _Line, Fun, Args}) ->
    Op    = cerl:c_var({fn_atom(Fun), length(Args)}),
    CArgs = [gen_expr(A) || A <- Args],
    cerl:c_apply(Op, CArgs);

%% Module.function call
gen_expr({dot_call, _Line, Mod, Fun, Args}) ->
    {ErlMod, ErlFun} = resolve_dot_call(Mod, Fun),
    CArgs = [gen_expr(A) || A <- Args],
    cerl:c_call(cerl:c_atom(ErlMod), cerl:c_atom(ErlFun), CArgs);

%% Binary operators
gen_expr({op, _Line, Op, Lhs, Rhs}) ->
    gen_op(Op, gen_expr(Lhs), gen_expr(Rhs));

%% Unary operators
gen_expr({unary, _Line, 'not', Expr}) ->
    cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('not'), [gen_expr(Expr)]);
gen_expr({unary, _Line, '-', Expr}) ->
    cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('-'), [gen_expr(Expr)]);

%% Variable assignment: x = expr  (let binding)
gen_expr({assign, _Line, {var, _, VName}, Expr}) ->
    Var  = cerl:c_var(var_atom(VName)),
    %% A let that returns the bound variable.
    cerl:c_let([Var], gen_expr(Expr), Var);

%% Variable reference
gen_expr({var, _Line, Name}) ->
    cerl:c_var(var_atom(Name));

%% Literals
gen_expr({integer, _Line, V})  -> cerl:c_int(V);
gen_expr({float,   _Line, V})  -> cerl:c_float(V);
gen_expr({atom,    _Line, V})  -> cerl:c_atom(resolve_atom(V));
gen_expr({boolean, _Line, V})  -> cerl:c_atom(V);
gen_expr({nil,     _Line})     -> cerl:c_atom(nil);

%% String → UTF-8 binary via cerl:abstract/1.
gen_expr({string, _Line, Bin}) when is_binary(Bin) ->
    cerl:abstract(Bin);

%% List
gen_expr({list, _Line, []}) ->
    cerl:c_nil();
gen_expr({list, _Line, [H | T]}) ->
    cerl:c_cons(gen_expr(H), gen_expr({list, 0, T}));

%% Tuple
gen_expr({tuple, _Line, Elements}) ->
    cerl:c_tuple([gen_expr(E) || E <- Elements]);

%% Map
gen_expr({map, _Line, Pairs}) ->
    Base   = cerl:abstract(#{}),
    KVs    = [cerl:c_map_pair(cerl:c_atom(K), gen_expr(V))
              || {K, V} <- Pairs],
    cerl:c_map(Base, KVs);

%% Closure / anonymous function: do |params| body end
gen_expr({block, _Line, Params, Body}) ->
    ParamVars = [cerl:c_var(var_atom(P)) || {var, _, P} <- Params],
    BodyExpr  = gen_body(Body),
    cerl:c_fun(ParamVars, BodyExpr);

%% try/rescue expression (L4)
gen_expr({try_expr, _Line, Body, RescueClauses}) ->
    CerlBody = gen_body(Body),
    %% Bind the success value to a fresh variable and return it.
    SuccessVar = cerl:c_var('_try_val'),
    %% Build catch clauses from rescue clauses.
    %% Erlang try/catch receives {Class, Reason, Stacktrace}.
    ExcClass = cerl:c_var('_exc_class'),
    ExcVal   = cerl:c_var('_exc_val'),
    ExcTrace = cerl:c_var('_exc_trace'),
    CatchClauses = [gen_rescue_clause(RC) || RC <- RescueClauses],
    %% Add a catch-all rethrow clause at the end.
    RethrowPat   = cerl:c_tuple([ExcClass, ExcVal, ExcTrace]),
    RethrowBody  = cerl:c_primop(
        cerl:c_atom(raise),
        [ExcTrace, ExcVal]),
    RethrowClause = cerl:c_clause([RethrowPat], cerl:c_atom(true), RethrowBody),
    AllCatchClauses = CatchClauses ++ [RethrowClause],
    CatchVar = cerl:c_var('_catch_reason'),
    CatchCase = cerl:c_case(CatchVar, AllCatchClauses),
    cerl:c_try(CerlBody, [SuccessVar], SuccessVar,
               [ExcClass, ExcVal, ExcTrace],
               cerl:c_let([CatchVar],
                          cerl:c_tuple([ExcClass, ExcVal, ExcTrace]),
                          CatchCase));

%% Range: 1..10 => lists:seq(1, 10)
gen_expr({range, _Line, From, To}) ->
    cerl:c_call(cerl:c_atom(lists), cerl:c_atom(seq),
                [gen_expr(From), gen_expr(To)]);

%% Map field access: user.name => maps:get(name, User)
gen_expr({field_access, _Line, Expr, Field}) ->
    cerl:c_call(cerl:c_atom(maps), cerl:c_atom(get),
                [cerl:c_atom(Field), gen_expr(Expr)]);

gen_expr(Unknown) ->
    error({unsupported_ast_node, Unknown}).

%% ── Case clauses ───────────────────────────────────────────────────────────

gen_case_clause({case_clause, _Line, Patterns, Guard, Body}) ->
    CerlPats  = [gen_pattern(P) || P <- Patterns],
    CerlGuard = case Guard of
        none -> cerl:c_atom(true);
        _    -> gen_expr(Guard)
    end,
    CerlBody  = gen_body(Body),
    cerl:c_clause(CerlPats, CerlGuard, CerlBody).

%% ── Rescue clauses (try/rescue) ──────────────────────────────────────────
%%
%% Each rescue clause pattern matches the catch tuple {Class, Reason, Trace}.
%% We match on the Reason component; Class defaults to 'throw'.

gen_rescue_clause({rescue_clause, _Line, Pat, Body}) ->
    ExcClass = cerl:c_var('_exc_class'),
    ExcTrace = cerl:c_var('_exc_trace'),
    CerlPat  = cerl:c_tuple([ExcClass, gen_pattern(Pat), ExcTrace]),
    CerlBody = gen_body(Body),
    cerl:c_clause([CerlPat], cerl:c_atom(true), CerlBody).

%% ── Patterns ───────────────────────────────────────────────────────────────
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

%% ── Binary operators ───────────────────────────────────────────────────────

gen_op('+',   L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('+'),   [L, R]);
gen_op('-',   L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('-'),   [L, R]);
gen_op('*',   L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('*'),   [L, R]);
gen_op('/',   L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('/'),   [L, R]);
gen_op('==',  L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('=='),  [L, R]);
gen_op('!=',  L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('/='),  [L, R]);
gen_op('<',   L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('<'),   [L, R]);
gen_op('>',   L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('>'),   [L, R]);
gen_op('<=',  L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('=<'),  [L, R]);
gen_op('>=',  L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('>='),  [L, R]);
gen_op('and', L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('and'), [L, R]);
gen_op('or',  L, R) -> cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('or'),  [L, R]);
gen_op('<>',  L, R) ->
    %% Binary concatenation via erlang:binary_part trick — use list_to_binary
    cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('binary_part'),
        [cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('list_to_binary'),
            [cerl:c_cons(L, cerl:c_cons(R, cerl:c_nil()))]),
         cerl:c_int(0),
         cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('+'),
            [cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('byte_size'), [L]),
             cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('byte_size'), [R])])]).

%% ── Module/function name resolution ───────────────────────────────────────

resolve_dot_call('IO', Fun) ->
    {winn_runtime, list_to_atom("io." ++ atom_to_list(Fun))};
resolve_dot_call('String', Fun) ->
    {winn_runtime, list_to_atom("string." ++ atom_to_list(Fun))};
resolve_dot_call('Enum', Fun) ->
    {winn_runtime, list_to_atom("enum." ++ atom_to_list(Fun))};
resolve_dot_call('Map', Fun) ->
    {winn_runtime, list_to_atom("map." ++ atom_to_list(Fun))};
resolve_dot_call('List', Fun) ->
    {winn_runtime, list_to_atom("list." ++ atom_to_list(Fun))};
resolve_dot_call('GenServer', Fun) -> {gen_server, Fun};
resolve_dot_call('Supervisor', Fun) -> {supervisor, Fun};
resolve_dot_call('Repo', Fun)       -> {winn_repo, Fun};
resolve_dot_call('Changeset', Fun)  -> {winn_changeset, Fun};
resolve_dot_call('System', Fun) ->
    {winn_runtime, list_to_atom("system." ++ atom_to_list(Fun))};
resolve_dot_call('UUID', Fun) ->
    {winn_runtime, list_to_atom("uuid." ++ atom_to_list(Fun))};
resolve_dot_call('DateTime', Fun) ->
    {winn_runtime, list_to_atom("datetime." ++ atom_to_list(Fun))};
resolve_dot_call('Logger', Fun)  -> {winn_logger, Fun};
resolve_dot_call('Crypto', Fun)  -> {winn_crypto, Fun};
resolve_dot_call('HTTP', Fun)    -> {winn_http, Fun};
resolve_dot_call('Config', Fun)  -> {winn_config, Fun};
resolve_dot_call('Task', Fun)    -> {winn_task, Fun};
resolve_dot_call('JWT', Fun)     -> {winn_jwt, Fun};
resolve_dot_call('WS', Fun)      -> {winn_ws, Fun};
resolve_dot_call('Server', Fun)  -> {winn_server, Fun};
resolve_dot_call('JSON', Fun)    -> {winn_json, Fun};
resolve_dot_call('Winn', Fun)    -> {winn_runtime, Fun};
resolve_dot_call('Retry', Fun)    -> {winn_retry, Fun};
resolve_dot_call('Timer', Fun)    -> {winn_timer, Fun};
resolve_dot_call('File', Fun)     -> {winn_file, Fun};
resolve_dot_call('Regex', Fun) -> {winn_regex, Fun};
resolve_dot_call('Protocol', Fun) -> {winn_protocol, Fun};
resolve_dot_call('Health', Fun)   -> {winn_health, Fun};
resolve_dot_call('Metrics', Fun)  -> {winn_metrics, Fun};
resolve_dot_call('Agent', Fun)    -> {winn_agent, Fun};
resolve_dot_call('ReplBindings', get) -> {winn_repl, get_binding};
resolve_dot_call(Mod, Fun) ->
    ErlMod = list_to_atom(string:lowercase(atom_to_list(Mod))),
    {ErlMod, Fun}.

%% ── Name helpers ───────────────────────────────────────────────────────────

winn_module_atom(Name) when is_atom(Name) ->
    list_to_atom(string:lowercase(atom_to_list(Name))).

fn_atom(Name) when is_atom(Name) -> Name.

%% Module name references (PascalCase) used as values are lowercased
%% to match compiled module names: Post -> post.
%% Regular atoms (:ok, :error, etc.) are left as-is.
resolve_atom(V) when is_atom(V) ->
    Str = atom_to_list(V),
    case Str of
        [C | _] when C >= $A, C =< $Z ->
            list_to_atom(string:lowercase(Str));
        _ ->
            V
    end.

%% Capitalise the first letter of a variable name for Core Erlang convention.
%% Only lowercase ASCII letters are capitalised; _ and uppercase are left alone.
var_atom(Name) when is_atom(Name) ->
    case atom_to_list(Name) of
        [C | Rest] when C >= $a, C =< $z ->
            list_to_atom([(C - 32) | Rest]);
        Chars ->
            list_to_atom(Chars)
    end.

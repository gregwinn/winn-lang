%% winn_codegen.erl
%% Translates the lowered Winn AST into Core Erlang using the cerl module.
%%
%% Orchestrates code generation across submodules:
%%   winn_codegen_resolve  — module name resolution (resolve_dot_call)
%%   winn_codegen_pattern  — pattern and parameter generation

-module(winn_codegen).
-export([gen/1]).

-import(winn_codegen_resolve, [resolve_dot_call/2, resolve_atom/1,
                               winn_module_atom/1, fn_atom/1, var_atom/1]).
-import(winn_codegen_pattern, [gen_pattern/1, gen_param/1]).

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

%% ── Body (expression sequence) ───────────────────────────────────────────
%% Last expression is the return value.
%% Assignments scope over the rest of the body via let bindings.

gen_body([]) ->
    cerl:c_atom(nil);
gen_body([Single]) ->
    gen_expr(Single);
gen_body([{assign, _Line, {var, _, VName}, Expr} | Rest]) ->
    Var = cerl:c_var(var_atom(VName)),
    cerl:c_let([Var], gen_expr(Expr), gen_body(Rest));
gen_body([{pat_assign_case, _Line, _Pat, CaseExpr} | Rest]) ->
    %% Pattern assignment: bind the matched value, then continue with
    %% the pattern variables in scope via the case clause.
    %% We generate: case Expr of Pat -> <rest of body> end
    {case_expr, _, Scrutinee, [{case_clause, _CLine, Pats, Guard, _Body}]} = CaseExpr,
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
    SuccessVar = cerl:c_var('_try_val'),
    ExcClass = cerl:c_var('_exc_class'),
    ExcVal   = cerl:c_var('_exc_val'),
    ExcTrace = cerl:c_var('_exc_trace'),
    CatchClauses = [gen_rescue_clause(RC) || RC <- RescueClauses],
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

gen_rescue_clause({rescue_clause, _Line, Pat, Body}) ->
    ExcClass = cerl:c_var('_exc_class'),
    ExcTrace = cerl:c_var('_exc_trace'),
    CerlPat  = cerl:c_tuple([ExcClass, gen_pattern(Pat), ExcTrace]),
    CerlBody = gen_body(Body),
    cerl:c_clause([CerlPat], cerl:c_atom(true), CerlBody).

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
    %% Binary concatenation
    cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('binary_part'),
        [cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('list_to_binary'),
            [cerl:c_cons(L, cerl:c_cons(R, cerl:c_nil()))]),
         cerl:c_int(0),
         cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('+'),
            [cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('byte_size'), [L]),
             cerl:c_call(cerl:c_atom(erlang), cerl:c_atom('byte_size'), [R])])]).

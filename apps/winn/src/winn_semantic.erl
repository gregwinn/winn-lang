%% winn_semantic.erl
%% Semantic analysis: scope resolution, arity checking, error accumulation.
%%
%% Phase 1: Basic validation — detect undefined module names, empty function
%% bodies, and collect errors without crashing.
%% Phase 2 will add: full scope analysis, variable binding checks.

-module(winn_semantic).
-export([analyse/1]).

%% Analyse a transformed program. Returns {ok, Forms} or {error, Errors}.
analyse(Forms) ->
    {Result, Errors} = lists:mapfoldl(
        fun(Form, Acc) -> analyse_form(Form, Acc) end,
        [],
        Forms
    ),
    case Errors of
        [] -> {ok, Result};
        _  -> {error, lists:reverse(Errors)}
    end.

%% ── Top-level forms ────────────────────────────────────────────────────────

analyse_form({module, Line, Name, Body}, Errors) ->
    {AnalysedBody, Errors1} = lists:mapfoldl(
        fun(F, Acc) -> analyse_form(F, Acc) end,
        Errors,
        Body
    ),
    {{module, Line, Name, AnalysedBody}, Errors1};

analyse_form({function, Line, Name, Params, []}, Errors) ->
    %% Warn on empty body — will return nil.
    Warn = {warning, Line, Name, "function has empty body, returns nil"},
    {{function, Line, Name, Params, []}, [Warn | Errors]};

analyse_form({function, Line, Name, Params, Body}, Errors) ->
    {AnalysedBody, Errors1} = lists:mapfoldl(
        fun(Expr, Acc) -> analyse_expr(Expr, #{}, Acc) end,
        Errors,
        Body
    ),
    {{function, Line, Name, Params, AnalysedBody}, Errors1};

analyse_form(Other, Errors) ->
    {Other, Errors}.

%% ── Expressions ───────────────────────────────────────────────────────────

analyse_expr({call, Line, Fun, Args}, _Scope, Errors) ->
    {AnalysedArgs, Errors1} = analyse_args(Args, _Scope, Errors),
    {{call, Line, Fun, AnalysedArgs}, Errors1};

analyse_expr({dot_call, Line, Mod, Fun, Args}, Scope, Errors) ->
    {AnalysedArgs, Errors1} = analyse_args(Args, Scope, Errors),
    {{dot_call, Line, Mod, Fun, AnalysedArgs}, Errors1};

analyse_expr({op, Line, Op, Lhs, Rhs}, Scope, Errors) ->
    {L2, E1} = analyse_expr(Lhs, Scope, Errors),
    {R2, E2} = analyse_expr(Rhs, Scope, E1),
    {{op, Line, Op, L2, R2}, E2};

analyse_expr({unary, Line, Op, Expr}, Scope, Errors) ->
    {E2, Errors1} = analyse_expr(Expr, Scope, Errors),
    {{unary, Line, Op, E2}, Errors1};

analyse_expr({assign, Line, Pat, Expr}, Scope, Errors) ->
    {E2, Errors1} = analyse_expr(Expr, Scope, Errors),
    {{assign, Line, Pat, E2}, Errors1};

analyse_expr({list, Line, Elems}, Scope, Errors) ->
    {Elems2, E1} = analyse_args(Elems, Scope, Errors),
    {{list, Line, Elems2}, E1};

analyse_expr({tuple, Line, Elems}, Scope, Errors) ->
    {Elems2, E1} = analyse_args(Elems, Scope, Errors),
    {{tuple, Line, Elems2}, E1};

analyse_expr({map, Line, Pairs}, Scope, Errors) ->
    {Pairs2, E1} = lists:mapfoldl(
        fun({K, V}, Acc) ->
            {V2, Acc2} = analyse_expr(V, Scope, Acc),
            {{K, V2}, Acc2}
        end,
        Errors,
        Pairs
    ),
    {{map, Line, Pairs2}, E1};

analyse_expr(Leaf, _Scope, Errors) ->
    {Leaf, Errors}.

analyse_args(Args, Scope, Errors) ->
    lists:mapfoldl(
        fun(A, Acc) -> analyse_expr(A, Scope, Acc) end,
        Errors,
        Args
    ).

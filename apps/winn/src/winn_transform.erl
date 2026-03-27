%% winn_transform.erl
%% AST lowering and desugaring pass.
%%
%% Phase 1: Desugar pipe chains into nested calls.
%%   a |> b(x) |> c(y)  =>  c(b(a, x), y)
%%
%% Phase 2: Pattern matching support.
%%   - Lift pattern params to case-wrapped function bodies.
%%   - Merge adjacent multi-clause functions (same name + arity) into one.
%%   - Desugar `match...end` blocks:
%%       `expr |> match ok v => body end`  =>  `case expr of {ok, V} -> body end`
%%       `match expr ok v => body end`     =>  `case expr of {ok, V} -> body end`

-module(winn_transform).
-export([transform/1]).

%% ── Entry point ───────────────────────────────────────────────────────────

%% Transform a parsed program (list of top-level forms).
transform(Forms) when is_list(Forms) ->
    lists:map(fun transform_form/1, Forms).

%% ── Top-level forms ────────────────────────────────────────────────────────

transform_form({module, Line, Name, Body}) ->
    %% Separate use directives, schema defs, and regular functions.
    {UseDirs, Rest1}    = lists:partition(fun({use_directive,_,_,_}) -> true; (_) -> false end, Body),
    {SchemaDefs, Fns}   = lists:partition(fun({schema_def,_,_,_})    -> true; (_) -> false end, Rest1),

    %% Expand use directives.
    Expanded       = [expand_use(ULine, Mod, Sub, Name) || {use_directive, ULine, Mod, Sub} <- UseDirs],
    BehaviourAttrs = [Attr || {behaviour, Attr, _} <- Expanded]
                  ++ [Attr || {behaviour_only, Attr} <- Expanded],
    SyntheticFns   = [Fn   || {behaviour, _, Fn}   <- Expanded],

    %% Expand schema defs into generated functions, then case-wrap pattern params.
    SchemaFns = [transform_function(F)
                 || F <- lists:append([expand_schema_def(SD) || SD <- SchemaDefs])],

    %% Transform and merge regular functions.
    Pass1  = [transform_function(F) || F <- Fns],
    Merged = merge_fn_clauses(SchemaFns ++ Pass1),

    {module, Line, Name, BehaviourAttrs ++ SyntheticFns ++ Merged};
transform_form(Other) ->
    Other.

%% ── Use directive expansion ──────────────────────────────────────────────

lower_module_atom(Name) when is_atom(Name) ->
    list_to_atom(string:lowercase(atom_to_list(Name))).

expand_use(Line, 'Winn', 'GenServer', ModName) ->
    ModAtom = lower_module_atom(ModName),
    Attr = {behaviour_attr, Line, gen_server},
    StartLink = {function, Line, start_link, [{var, Line, args}],
        [{dot_call, Line, 'GenServer', start_link, [
            {tuple, Line, [{atom, Line, local}, {atom, Line, ModAtom}]},
            {atom, Line, ModAtom},
            {var, Line, args},
            {list, Line, []}
        ]}]},
    {behaviour, Attr, StartLink};
expand_use(Line, 'Winn', 'Supervisor', ModName) ->
    ModAtom = lower_module_atom(ModName),
    Attr = {behaviour_attr, Line, supervisor},
    StartLink = {function, Line, start_link, [{var, Line, args}],
        [{dot_call, Line, 'Supervisor', start_link, [
            {tuple, Line, [{atom, Line, local}, {atom, Line, ModAtom}]},
            {atom, Line, ModAtom},
            {var, Line, args}
        ]}]},
    {behaviour, Attr, StartLink};
expand_use(Line, 'Winn', 'Application', _ModName) ->
    Attr = {behaviour_attr, Line, application},
    {behaviour_only, Attr};
expand_use(Line, 'Winn', 'WebSocket', _ModName) ->
    Attr = {behaviour_attr, Line, winn_ws_handler},
    {behaviour_only, Attr};
expand_use(Line, 'Winn', 'Task', _ModName) ->
    Attr = {behaviour_attr, Line, winn_task},
    {behaviour_only, Attr};
expand_use(_Line, 'Winn', 'Schema', _ModName) ->
    {schema_use, none}.

%% ── Schema definition expansion ──────────────────────────────────────────

expand_schema_def({schema_def, L, TableBin, Fields}) ->
    %% __schema__(:source) -> table name binary
    SourceFn = {function, L, '__schema__', [{pat_atom, L, source}],
                [{string, L, TableBin}]},

    %% __schema__(:fields) -> list of field name atoms
    FieldsFn = {function, L, '__schema__', [{pat_atom, L, fields}],
                [{list, L, [{atom, L, FName} || {field, _, FName, _} <- Fields]}]},

    %% __schema__(:types) -> map of field -> type
    TypesFn = {function, L, '__schema__', [{pat_atom, L, types}],
               [{map, L, [{FName, {atom, L, FType}} || {field, _, FName, FType} <- Fields]}]},

    %% new(attrs) -> Map.merge(%{field: nil,...}, attrs)
    NilFields = [{FName, {nil, L}} || {field, _, FName, _} <- Fields],
    NewFn = {function, L, new, [{var, L, attrs}],
             [{dot_call, L, 'Map', merge, [
                 {map, L, NilFields},
                 {var, L, attrs}
             ]}]},

    [SourceFn, FieldsFn, TypesFn, NewFn].

%% ── Function transformation ────────────────────────────────────────────────

transform_function({function_g, Line, Name, Params, Guard, Body}) ->
    TransBody  = transform_seq(Body),
    TransGuard = transform_expr(Guard),
    Arity   = length(Params),
    ArgVars = fresh_arg_vars(Line, Arity),
    Scrutinee = case Arity of
        1 -> hd(ArgVars);
        _ -> {tuple, Line, ArgVars}
    end,
    CasePat = case Arity of
        1 -> hd(Params);
        _ -> {pat_tuple, Line, Params}
    end,
    CaseClause = {case_clause, Line, [CasePat], TransGuard, TransBody},
    {function, Line, Name, ArgVars, [{case_expr, Line, Scrutinee, [CaseClause]}]};

transform_function({function, Line, Name, Params, Body}) ->
    TransBody = transform_seq(Body),
    %% Always case-wrap so that multi-clause functions (some guarded, some not)
    %% can be merged into a single case expression.
    wrap_in_case(Line, Name, Params, TransBody).

%% Wrap pattern-param function into a case expression.
%%   def foo({:ok, x}) body end
%% becomes:
%%   def foo(_arg0) case _arg0 of {:ok, X} -> body end end
%%
%% For multi-arg functions, scrutinee is a tuple of all args:
%%   def foo(a, {:ok, b}) body end
%% becomes:
%%   def foo(_arg0, _arg1) case {_arg0, _arg1} of {A, {:ok, B}} -> body end end
wrap_in_case(Line, Name, Params, Body) ->
    Arity = length(Params),
    ArgVars = fresh_arg_vars(Line, Arity),
    Scrutinee = case Arity of
        1 -> hd(ArgVars);
        _ -> {tuple, Line, ArgVars}
    end,
    CasePat = case Arity of
        1 -> hd(Params);
        _ -> {pat_tuple, Line, Params}
    end,
    CaseClause = {case_clause, Line, [CasePat], none, Body},
    {function, Line, Name, ArgVars, [{case_expr, Line, Scrutinee, [CaseClause]}]}.

fresh_arg_vars(Line, Arity) ->
    [{var, Line, list_to_atom("_arg" ++ integer_to_list(I))}
     || I <- lists:seq(0, Arity - 1)].

%% ── Multi-clause function merging ─────────────────────────────────────────
%%
%% Adjacent function nodes with the same name and arity are merged into a
%% single function whose body is a case expression with all clauses.
%%
%% Input:
%%   {function, L, foo, [_arg0], [{case_expr, L, _arg0, [Clause1]}]}
%%   {function, L, foo, [_arg0], [{case_expr, L, _arg0, [Clause2]}]}
%%
%% Output:
%%   {function, L, foo, [_arg0], [{case_expr, L, _arg0, [Clause1, Clause2]}]}

merge_fn_clauses([]) ->
    [];
merge_fn_clauses([{function, L, Name, Args, [{case_expr, CL, Scr, Clauses}]} | Rest]) ->
    Arity = length(Args),
    {Same, Remaining} = take_matching_fns(Name, Arity, Rest),
    AllClauses = Clauses ++ lists:append(
        [Cs || {function,_,_,_,[{case_expr,_,_,Cs}]} <- Same]
    ),
    Merged = {function, L, Name, Args, [{case_expr, CL, Scr, AllClauses}]},
    [Merged | merge_fn_clauses(Remaining)];
merge_fn_clauses([F | Rest]) ->
    [F | merge_fn_clauses(Rest)].

%% Take consecutive functions with the same name/arity that are already
%% case-wrapped (so they came from pattern-param defs).
take_matching_fns(Name, Arity,
    [{function,_,Name,Args,[{case_expr,_,_,_}]} = F | Rest])
    when length(Args) =:= Arity ->
    {More, Remaining} = take_matching_fns(Name, Arity, Rest),
    {[F | More], Remaining};
take_matching_fns(_, _, Rest) ->
    {[], Rest}.

%% ── Expression sequences ──────────────────────────────────────────────────

transform_seq(Exprs) ->
    lists:map(fun transform_expr/1, Exprs).

%% ── Expressions ───────────────────────────────────────────────────────────

%% Pipe into a block_call: expr |> foo() do |x| body end
transform_expr({pipe, Line, Lhs, {block_call, BLine, CallExpr, BlockParams, BlockBody}}) ->
    TransLhs  = transform_expr(Lhs),
    TransBody = transform_seq(BlockBody),
    Block     = {block, BLine, BlockParams, TransBody},
    case transform_expr(CallExpr) of
        {call, CLine, Fun, Args} ->
            {call, CLine, Fun, [TransLhs | [transform_expr(A) || A <- Args]] ++ [Block]};
        {dot_call, CLine, Mod, Fun, Args} ->
            {dot_call, CLine, Mod, Fun, [TransLhs | [transform_expr(A) || A <- Args]] ++ [Block]};
        _ ->
            error({unsupported_pipe_block_target, Line})
    end;

%% Standalone block_call: foo() do |x| body end
transform_expr({block_call, Line, CallExpr, BlockParams, BlockBody}) ->
    TransBody = transform_seq(BlockBody),
    Block     = {block, Line, BlockParams, TransBody},
    case transform_expr(CallExpr) of
        {call, CLine, Fun, Args} ->
            {call, CLine, Fun, [transform_expr(A) || A <- Args] ++ [Block]};
        {dot_call, CLine, Mod, Fun, Args} ->
            {dot_call, CLine, Mod, Fun, [transform_expr(A) || A <- Args] ++ [Block]};
        _ ->
            error({unsupported_block_call_target, Line})
    end;

%% Pipe into a match block: `expr |> match clauses end`
%% Desugar to a case expression with the pipe LHS as scrutinee.
transform_expr({pipe, Line, Lhs, {match_block, _, none, Clauses}}) ->
    TransLhs = transform_expr(Lhs),
    TransClauses = [transform_match_clause(C) || C <- Clauses],
    {case_expr, Line, TransLhs, TransClauses};

%% Regular pipe: desugar to nested call.
transform_expr({pipe, Line, Lhs, Rhs}) ->
    TransLhs = transform_expr(Lhs),
    case transform_expr(Rhs) of
        {call, CLine, Fun, Args} ->
            {call, CLine, Fun, [TransLhs | Args]};
        {dot_call, CLine, Mod, Fun, Args} ->
            {dot_call, CLine, Mod, Fun, [TransLhs | Args]};
        Other ->
            %% Non-call RHS — leave as a pipe_apply for error reporting.
            {pipe_apply, Line, TransLhs, Other}
    end;

%% Standalone match block with an explicit scrutinee.
transform_expr({match_block, Line, Scrutinee, Clauses}) when Scrutinee =/= none ->
    TransScrutinee = transform_expr(Scrutinee),
    TransClauses = [transform_match_clause(C) || C <- Clauses],
    {case_expr, Line, TransScrutinee, TransClauses};

%% Standalone match block with no scrutinee — semantic error, pass through.
transform_expr({match_block, Line, none, Clauses}) ->
    TransClauses = [transform_match_clause(C) || C <- Clauses],
    {match_block_no_scrutinee, Line, TransClauses};

%% Recursive cases.
transform_expr({call, Line, Fun, Args}) ->
    {call, Line, Fun, lists:map(fun transform_expr/1, Args)};
transform_expr({dot_call, Line, Mod, Fun, Args}) ->
    {dot_call, Line, Mod, Fun, lists:map(fun transform_expr/1, Args)};
transform_expr({op, Line, Op, Lhs, Rhs}) ->
    {op, Line, Op, transform_expr(Lhs), transform_expr(Rhs)};
transform_expr({unary, Line, Op, Expr}) ->
    {unary, Line, Op, transform_expr(Expr)};
transform_expr({assign, Line, Pat, Expr}) ->
    {assign, Line, Pat, transform_expr(Expr)};
transform_expr({list, Line, Elements}) ->
    {list, Line, lists:map(fun transform_expr/1, Elements)};
transform_expr({tuple, Line, Elements}) ->
    {tuple, Line, lists:map(fun transform_expr/1, Elements)};
transform_expr({map, Line, Pairs}) ->
    {map, Line, [{K, transform_expr(V)} || {K, V} <- Pairs]};

%% Block (closure) — body already transformed above, leave node intact.
transform_expr({block, Line, Params, Body}) ->
    {block, Line, Params, Body};

%% L1 — if/else desugared to case
transform_expr({if_expr, Line, Cond, Then, []}) ->
    TrueClause = {case_clause, Line, [{pat_atom, Line, true}], none, transform_seq(Then)},
    {case_expr, Line, transform_expr(Cond), [TrueClause]};

transform_expr({if_expr, Line, Cond, Then, Else}) ->
    TrueClause  = {case_clause, Line, [{pat_atom, Line, true}], none, transform_seq(Then)},
    FalseClause = {case_clause, Line, [{pat_wildcard, Line}],   none, transform_seq(Else)},
    {case_expr, Line, transform_expr(Cond), [TrueClause, FalseClause]};

%% L2 — switch desugared to case
transform_expr({switch_expr, Line, Scrutinee, Clauses}) ->
    CaseClauses = [{case_clause, CL, [Pat], Guard, transform_seq(Body)}
                   || {switch_clause, CL, Pat, Guard, Body} <- Clauses],
    {case_expr, Line, transform_expr(Scrutinee), CaseClauses};

%% L4 — try/rescue
transform_expr({try_expr, Line, TryBody, RescueClauses}) ->
    TransBody   = transform_seq(TryBody),
    TransRescue = [{rescue_clause, RL, Pat, transform_seq(RBody)}
                   || {rescue_clause, RL, Pat, RBody} <- RescueClauses],
    {try_expr, Line, TransBody, TransRescue};

%% Leaf nodes — no transformation needed.
transform_expr(Leaf) ->
    Leaf.

%% ── Match clause desugaring ────────────────────────────────────────────────
%%
%% ok_kw and err_kw are syntactic sugar for {ok, _} and {error, _} patterns.
%%
%%   ok v   =>  pattern: {pat_tuple, [{pat_atom, ok}, {var, v}]}
%%   err e  =>  pattern: {pat_tuple, [{pat_atom, error}, {var, e}]}

transform_match_clause({match_clause, Line, ok, PatternNode, Body}) ->
    OkPat = {pat_tuple, Line, [{pat_atom, Line, ok}, PatternNode]},
    TransBody = transform_seq(Body),
    {case_clause, Line, [OkPat], none, TransBody};
transform_match_clause({match_clause, Line, err, PatternNode, Body}) ->
    ErrPat = {pat_tuple, Line, [{pat_atom, Line, error}, PatternNode]},
    TransBody = transform_seq(Body),
    {case_clause, Line, [ErrPat], none, TransBody}.

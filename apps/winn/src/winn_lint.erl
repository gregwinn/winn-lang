%% winn_lint.erl
%% Static analysis linter for Winn source code.
%%
%% Parses source → walks AST → collects lint violations as diagnostics.
%% Violations use the same {Severity, Line, Rule, Message} format as
%% winn_semantic so they can be rendered by winn_errors:format_diagnostics/3.

-module(winn_lint).
-export([check_string/1, check_file/1]).

%% ── Public API ──────────────────────────────────────────────────────────

check_string(Source) when is_list(Source) ->
    case parse(Source) of
        {ok, AST} ->
            Violations = lint_forms(AST),
            {ok, lists:reverse(Violations)};
        {error, Reason} ->
            {error, Reason}
    end.

check_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> check_string(binary_to_list(Bin));
        {error, Reason} -> {error, {file_read, Path, Reason}}
    end.

%% ── Parse pipeline (same as formatter) ──────────────────────────────────

parse(Source) ->
    case winn_lexer:string(Source) of
        {ok, RawTokens, _} ->
            Tokens = winn_newline_filter:filter(RawTokens),
            case winn_parser:parse(Tokens) of
                {ok, AST} -> {ok, AST};
                {error, Reason} -> {error, {parse_error, Reason}}
            end;
        {error, Reason, _} ->
            {error, {lex_error, Reason}}
    end.

%% ── Top-level AST walking ───────────────────────────────────────────────

lint_forms(Forms) ->
    lists:foldl(fun lint_form/2, [], Forms).

lint_form({module, Line, Name, Body}, Acc) ->
    Acc1 = check_module_name(Line, Name, Acc),
    %% Collect imports and aliases, then check usage across module body
    Imports = collect_imports(Body),
    Aliases = collect_aliases(Body),
    Acc2 = lint_module_body(Body, Acc1),
    Acc3 = check_unused_imports(Imports, Body, Acc2),
    check_unused_aliases(Aliases, Body, Acc3);

lint_form({agent, Line, Name, Body}, Acc) ->
    Acc1 = check_module_name(Line, Name, Acc),
    Imports = collect_imports(Body),
    Aliases = collect_aliases(Body),
    Acc2 = lint_module_body(Body, Acc1),
    Acc3 = check_unused_imports(Imports, Body, Acc2),
    check_unused_aliases(Aliases, Body, Acc3);

lint_form(_Other, Acc) ->
    Acc.

lint_module_body(Body, Acc) ->
    lists:foldl(fun lint_body_form/2, Acc, Body).

lint_body_form({function, Line, Name, Params, Body}, Acc) ->
    Acc1 = check_function_name(Line, Name, Acc),
    Acc2 = check_empty_body(Line, Name, Body, Acc1),
    Acc3 = check_large_function(Line, Name, Body, Acc2),
    Acc4 = check_unused_variables(Line, Params, Body, Acc3),
    lint_exprs(Body, Acc4);

lint_body_form({function_g, Line, Name, Params, _Guard, Body}, Acc) ->
    Acc1 = check_function_name(Line, Name, Acc),
    Acc2 = check_empty_body(Line, Name, Body, Acc1),
    Acc3 = check_large_function(Line, Name, Body, Acc2),
    Acc4 = check_unused_variables(Line, Params, Body, Acc3),
    lint_exprs(Body, Acc4);

lint_body_form({agent_fn, Line, Name, Params, Body}, Acc) ->
    Acc1 = check_function_name(Line, Name, Acc),
    Acc2 = check_empty_body(Line, Name, Body, Acc1),
    Acc3 = check_unused_variables(Line, Params, Body, Acc2),
    lint_exprs(Body, Acc3);

lint_body_form({agent_fn_g, Line, Name, Params, _Guard, Body}, Acc) ->
    Acc1 = check_function_name(Line, Name, Acc),
    Acc2 = check_empty_body(Line, Name, Body, Acc1),
    Acc3 = check_unused_variables(Line, Params, Body, Acc2),
    lint_exprs(Body, Acc3);

lint_body_form({agent_cast_fn, Line, Name, Params, Body}, Acc) ->
    Acc1 = check_function_name(Line, Name, Acc),
    Acc2 = check_empty_body(Line, Name, Body, Acc1),
    Acc3 = check_unused_variables(Line, Params, Body, Acc2),
    lint_exprs(Body, Acc3);

lint_body_form(_Other, Acc) ->
    Acc.

%% ── Expression linting ──────────────────────────────────────────────────

lint_exprs(Exprs, Acc) when is_list(Exprs) ->
    lists:foldl(fun lint_expr/2, Acc, Exprs);
lint_exprs(Expr, Acc) ->
    lint_expr(Expr, Acc).

lint_expr({pipe, Line, Lhs, Rhs} = Pipe, Acc) ->
    %% Count pipe chain length to determine if it's a single pipe
    ChainLen = pipe_chain_length(Pipe),
    Acc1 = case ChainLen of
        1 ->
            [{warning, Line, single_pipe,
              "Single pipe — consider using a regular function call"} | Acc];
        _ -> Acc
    end,
    %% Check all pipe segments for pipe_into_literal
    Acc2 = check_pipe_chain_literals(Pipe, Acc1),
    %% Lint sub-expressions (skip pipe nodes themselves to avoid re-flagging)
    Acc3 = lint_pipe_leaves(Lhs, Acc2),
    lint_pipe_leaves(Rhs, Acc3);

lint_expr({if_expr, _Line, Cond, Then, Else}, Acc) ->
    Acc1 = check_redundant_boolean(Cond, Acc),
    Acc2 = lint_expr(Cond, Acc1),
    Acc3 = lint_exprs(Then, Acc2),
    lint_exprs(Else, Acc3);

lint_expr({op, _Line, _Op, Lhs, Rhs}, Acc) ->
    Acc1 = lint_expr(Lhs, Acc),
    lint_expr(Rhs, Acc1);

lint_expr({unary, _Line, _Op, Expr}, Acc) ->
    lint_expr(Expr, Acc);

lint_expr({assign, _Line, _Pat, Expr}, Acc) ->
    lint_expr(Expr, Acc);

lint_expr({call, _Line, _Fun, Args}, Acc) ->
    lint_exprs(Args, Acc);

lint_expr({dot_call, _Line, _Mod, _Fun, Args}, Acc) ->
    lint_exprs(Args, Acc);

lint_expr({list, _Line, Elems}, Acc) ->
    lint_exprs(Elems, Acc);

lint_expr({tuple, _Line, Elems}, Acc) ->
    lint_exprs(Elems, Acc);

lint_expr({map, _Line, Pairs}, Acc) ->
    lists:foldl(fun({_K, V}, A) -> lint_expr(V, A) end, Acc, Pairs);

lint_expr({switch_expr, _Line, Scrutinee, Clauses}, Acc) ->
    Acc1 = lint_expr(Scrutinee, Acc),
    lists:foldl(fun lint_clause/2, Acc1, Clauses);

lint_expr({match_block, _Line, Scrutinee, Clauses}, Acc) ->
    Acc1 = lint_expr(Scrutinee, Acc),
    lists:foldl(fun lint_clause/2, Acc1, Clauses);

lint_expr({try_expr, _Line, Body, Rescues}, Acc) ->
    Acc1 = lint_exprs(Body, Acc),
    lists:foldl(fun lint_clause/2, Acc1, Rescues);

lint_expr({for_expr, _Line, _Var, Iter, Body}, Acc) ->
    Acc1 = lint_expr(Iter, Acc),
    lint_exprs(Body, Acc1);

lint_expr({block, _Line, _Params, Body}, Acc) ->
    lint_exprs(Body, Acc);

lint_expr({field_access, _Line, Expr, _Field}, Acc) ->
    lint_expr(Expr, Acc);

lint_expr({range, _Line, From, To}, Acc) ->
    Acc1 = lint_expr(From, Acc),
    lint_expr(To, Acc1);

lint_expr(_Leaf, Acc) ->
    Acc.

lint_clause({clause, _Line, _Pat, Body}, Acc) ->
    lint_exprs(Body, Acc);
lint_clause({clause, _Line, _Pat, _Guard, Body}, Acc) ->
    lint_exprs(Body, Acc);
lint_clause({rescue_clause, _Line, _Pat, Body}, Acc) ->
    lint_exprs(Body, Acc);
lint_clause(_Other, Acc) ->
    Acc.

%% ── Rule: module_name_convention ────────────────────────────────────────

check_module_name(Line, Name, Acc) ->
    Str = atom_to_list(Name),
    case is_pascal_case(Str) of
        true  -> Acc;
        false ->
            Msg = io_lib:format("Module name '~s' should be PascalCase", [Str]),
            [{warning, Line, module_name_convention, lists:flatten(Msg)} | Acc]
    end.

is_pascal_case([C | _]) when C >= $A, C =< $Z -> true;
is_pascal_case(_) -> false.

%% ── Rule: function_name_convention ──────────────────────────────────────

check_function_name(Line, Name, Acc) ->
    Str = atom_to_list(Name),
    case is_snake_case(Str) of
        true  -> Acc;
        false ->
            Msg = io_lib:format("Function '~s' should be snake_case", [Str]),
            [{warning, Line, function_name_convention, lists:flatten(Msg)} | Acc]
    end.

is_snake_case([C | Rest]) when C >= $a, C =< $z ->
    is_snake_case_rest(Rest);
is_snake_case([$_ | Rest]) ->
    is_snake_case_rest(Rest);
is_snake_case(_) -> false.

is_snake_case_rest([]) -> true;
is_snake_case_rest([$? | []]) -> true;  %% trailing ? allowed
is_snake_case_rest([$!, $? | _]) -> false;
is_snake_case_rest([C | Rest]) when C >= $a, C =< $z -> is_snake_case_rest(Rest);
is_snake_case_rest([C | Rest]) when C >= $0, C =< $9 -> is_snake_case_rest(Rest);
is_snake_case_rest([$_ | Rest]) -> is_snake_case_rest(Rest);
is_snake_case_rest(_) -> false.

%% ── Rule: empty_function_body ───────────────────────────────────────────

check_empty_body(Line, Name, [], Acc) ->
    Msg = io_lib:format("Function '~s' has an empty body (returns nil)", [Name]),
    [{warning, Line, empty_function_body, lists:flatten(Msg)} | Acc];
check_empty_body(_Line, _Name, _Body, Acc) ->
    Acc.

%% ── Rule: large_function ────────────────────────────────────────────────

check_large_function(Line, Name, Body, Acc) when length(Body) > 50 ->
    Msg = io_lib:format("Function '~s' has ~B expressions (consider splitting)", [Name, length(Body)]),
    [{warning, Line, large_function, lists:flatten(Msg)} | Acc];
check_large_function(_Line, _Name, _Body, Acc) ->
    Acc.

%% ── Rule: redundant_boolean ─────────────────────────────────────────────

check_redundant_boolean({op, Line, '==', _Lhs, {boolean, _, true}}, Acc) ->
    [{warning, Line, redundant_boolean,
      "Redundant comparison: `x == true` — use `x` directly"} | Acc];
check_redundant_boolean({op, Line, '==', _Lhs, {boolean, _, false}}, Acc) ->
    [{warning, Line, redundant_boolean,
      "Redundant comparison: `x == false` — use `not x`"} | Acc];
check_redundant_boolean({op, Line, '!=', _Lhs, {boolean, _, true}}, Acc) ->
    [{warning, Line, redundant_boolean,
      "Redundant comparison: `x != true` — use `not x`"} | Acc];
check_redundant_boolean({op, Line, '!=', _Lhs, {boolean, _, false}}, Acc) ->
    [{warning, Line, redundant_boolean,
      "Redundant comparison: `x != false` — use `x` directly"} | Acc];
check_redundant_boolean(_Cond, Acc) ->
    Acc.

%% ── Rule: pipe_into_literal ─────────────────────────────────────────────

check_pipe_into_literal(Line, {integer, _, _}, Acc) ->
    [{warning, Line, pipe_into_literal,
      "Pipe into a literal value — did you mean to call a function?"} | Acc];
check_pipe_into_literal(Line, {float, _, _}, Acc) ->
    [{warning, Line, pipe_into_literal,
      "Pipe into a literal value — did you mean to call a function?"} | Acc];
check_pipe_into_literal(Line, {string, _, _}, Acc) ->
    [{warning, Line, pipe_into_literal,
      "Pipe into a literal value — did you mean to call a function?"} | Acc];
check_pipe_into_literal(Line, {boolean, _, _}, Acc) ->
    [{warning, Line, pipe_into_literal,
      "Pipe into a literal value — did you mean to call a function?"} | Acc];
check_pipe_into_literal(Line, {nil, _}, Acc) ->
    [{warning, Line, pipe_into_literal,
      "Pipe into a literal value — did you mean to call a function?"} | Acc];
check_pipe_into_literal(_Line, _Rhs, Acc) ->
    Acc.

%% ── Rule: single_pipe ──────────────────────────────────────────────────

pipe_chain_length({pipe, _, Lhs, _Rhs}) ->
    1 + pipe_chain_length(Lhs);
pipe_chain_length(_) ->
    0.

check_pipe_chain_literals({pipe, Line, Lhs, Rhs}, Acc) ->
    Acc1 = check_pipe_into_literal(Line, Rhs, Acc),
    check_pipe_chain_literals(Lhs, Acc1);
check_pipe_chain_literals(_NonPipe, Acc) ->
    Acc.

%% Lint the non-pipe leaves of a pipe chain
lint_pipe_leaves({pipe, _Line, Lhs, Rhs}, Acc) ->
    Acc1 = lint_pipe_leaves(Lhs, Acc),
    lint_pipe_leaves(Rhs, Acc1);
lint_pipe_leaves(Expr, Acc) ->
    lint_expr(Expr, Acc).


%% ── Rule: unused_variable ───────────────────────────────────────────────

check_unused_variables(_Line, Params, Body, Acc) ->
    Defined = collect_param_vars(Params),
    Used = collect_used_vars(Body, #{}),
    lists:foldl(fun({VarName, VarLine}, A) ->
        case is_ignorable_var(VarName) of
            true -> A;
            false ->
                case maps:is_key(VarName, Used) of
                    true -> A;
                    false ->
                        Msg = io_lib:format("Variable '~s' is assigned but never used (prefix with _ to ignore)", [VarName]),
                        [{warning, VarLine, unused_variable, lists:flatten(Msg)} | A]
                end
        end
    end, Acc, Defined).

is_ignorable_var("_") -> true;
is_ignorable_var([$_ | _]) -> true;
is_ignorable_var(_) -> false.

collect_param_vars(Params) ->
    lists:foldl(fun collect_param_var/2, [], Params).

collect_param_var({var, Line, Name}, Acc) ->
    [{atom_to_list(Name), Line} | Acc];
collect_param_var({pat_var, Line, Name}, Acc) ->
    [{atom_to_list(Name), Line} | Acc];
collect_param_var({default_param, Line, Name, _Val}, Acc) ->
    [{atom_to_list(Name), Line} | Acc];
collect_param_var({pat_tuple, _Line, Elems}, Acc) ->
    lists:foldl(fun collect_param_var/2, Acc, Elems);
collect_param_var({pat_list, _Line, Elems, Tail}, Acc) ->
    Acc1 = lists:foldl(fun collect_param_var/2, Acc, Elems),
    case Tail of
        none -> Acc1;
        _ -> collect_param_var(Tail, Acc1)
    end;
collect_param_var(_Other, Acc) ->
    Acc.

collect_used_vars(Exprs, Map) when is_list(Exprs) ->
    lists:foldl(fun(E, M) -> collect_used_vars(E, M) end, Map, Exprs);
collect_used_vars({var, _Line, Name}, Map) ->
    Map#{atom_to_list(Name) => true};
collect_used_vars({call, _Line, Fun, Args}, Map) ->
    %% The function name itself is a use if it's an atom referencing a var-like name
    Map1 = collect_used_vars(Args, Map),
    case Fun of
        {var, _, N} -> Map1#{atom_to_list(N) => true};
        _ -> Map1
    end;
collect_used_vars({dot_call, _Line, _Mod, _Fun, Args}, Map) ->
    collect_used_vars(Args, Map);
collect_used_vars({op, _Line, _Op, Lhs, Rhs}, Map) ->
    collect_used_vars(Rhs, collect_used_vars(Lhs, Map));
collect_used_vars({unary, _Line, _Op, Expr}, Map) ->
    collect_used_vars(Expr, Map);
collect_used_vars({assign, _Line, _Pat, Expr}, Map) ->
    collect_used_vars(Expr, Map);
collect_used_vars({if_expr, _Line, Cond, Then, Else}, Map) ->
    M1 = collect_used_vars(Cond, Map),
    M2 = collect_used_vars(Then, M1),
    collect_used_vars(Else, M2);
collect_used_vars({pipe, _Line, Lhs, Rhs}, Map) ->
    collect_used_vars(Rhs, collect_used_vars(Lhs, Map));
collect_used_vars({list, _Line, Elems}, Map) ->
    collect_used_vars(Elems, Map);
collect_used_vars({tuple, _Line, Elems}, Map) ->
    collect_used_vars(Elems, Map);
collect_used_vars({map, _Line, Pairs}, Map) ->
    lists:foldl(fun({_K, V}, M) -> collect_used_vars(V, M) end, Map, Pairs);
collect_used_vars({switch_expr, _Line, Scrutinee, Clauses}, Map) ->
    M1 = collect_used_vars(Scrutinee, Map),
    lists:foldl(fun collect_clause_vars/2, M1, Clauses);
collect_used_vars({match_block, _Line, Scrutinee, Clauses}, Map) ->
    M1 = collect_used_vars(Scrutinee, Map),
    lists:foldl(fun collect_clause_vars/2, M1, Clauses);
collect_used_vars({try_expr, _Line, Body, Rescues}, Map) ->
    M1 = collect_used_vars(Body, Map),
    lists:foldl(fun collect_clause_vars/2, M1, Rescues);
collect_used_vars({for_expr, _Line, _Var, Iter, Body}, Map) ->
    M1 = collect_used_vars(Iter, Map),
    collect_used_vars(Body, M1);
collect_used_vars({block, _Line, _Params, Body}, Map) ->
    collect_used_vars(Body, Map);
collect_used_vars({field_access, _Line, Expr, _Field}, Map) ->
    collect_used_vars(Expr, Map);
collect_used_vars({range, _Line, From, To}, Map) ->
    collect_used_vars(To, collect_used_vars(From, Map));
collect_used_vars({interp_string, _Line, Parts}, Map) ->
    lists:foldl(fun
        ({expr, E}, M) -> collect_used_vars(E, M);
        (_, M) -> M
    end, Map, Parts);
collect_used_vars(_Leaf, Map) ->
    Map.

collect_clause_vars({clause, _Line, _Pat, Body}, Map) ->
    collect_used_vars(Body, Map);
collect_clause_vars({clause, _Line, _Pat, _Guard, Body}, Map) ->
    collect_used_vars(Body, Map);
collect_clause_vars({rescue_clause, _Line, _Pat, Body}, Map) ->
    collect_used_vars(Body, Map);
collect_clause_vars(_Other, Map) ->
    Map.

%% ── Rule: unused_import ─────────────────────────────────────────────────

collect_imports(Body) ->
    [{Line, Name} || {import_directive, Line, Name} <- Body].

check_unused_imports(Imports, Body, Acc) ->
    CalledMods = collect_called_modules(Body),
    lists:foldl(fun({Line, Name}, A) ->
        ModStr = atom_to_list(Name),
        case lists:member(ModStr, CalledMods) of
            true -> A;
            false ->
                Msg = io_lib:format("Unused import: '~s'", [ModStr]),
                [{warning, Line, unused_import, lists:flatten(Msg)} | A]
        end
    end, Acc, Imports).

%% ── Rule: unused_alias ──────────────────────────────────────────────────

collect_aliases(Body) ->
    lists:filtermap(fun
        ({alias_directive, Line, _Full, Short}) -> {true, {Line, Short}};
        ({alias_directive, Line, Full}) ->
            %% Single-arg alias: MyApp.Router → alias is Router
            Parts = string:split(atom_to_list(Full), ".", all),
            Short = list_to_atom(lists:last(Parts)),
            {true, {Line, Short}};
        (_) -> false
    end, Body).

check_unused_aliases(Aliases, Body, Acc) ->
    CalledMods = collect_called_modules(Body),
    lists:foldl(fun({Line, Name}, A) ->
        ModStr = atom_to_list(Name),
        case lists:member(ModStr, CalledMods) of
            true -> A;
            false ->
                Msg = io_lib:format("Unused alias: '~s'", [ModStr]),
                [{warning, Line, unused_alias, lists:flatten(Msg)} | A]
        end
    end, Acc, Aliases).

%% Collect all module names referenced in dot_call expressions
collect_called_modules(Forms) ->
    collect_called_modules(Forms, []).

collect_called_modules([], Acc) ->
    lists:usort(Acc);
collect_called_modules([Form | Rest], Acc) ->
    Acc1 = collect_calls_from_form(Form, Acc),
    collect_called_modules(Rest, Acc1);
collect_called_modules(Other, Acc) ->
    collect_calls_from_form(Other, Acc).

collect_calls_from_form({dot_call, _Line, Mod, _Fun, Args}, Acc) when is_atom(Mod) ->
    Acc1 = [atom_to_list(Mod) | Acc],
    collect_called_modules(Args, Acc1);
collect_calls_from_form({dot_call, _Line, {atom, _, Mod}, _Fun, Args}, Acc) ->
    Acc1 = [atom_to_list(Mod) | Acc],
    collect_called_modules(Args, Acc1);
collect_calls_from_form({function, _Line, _Name, _Params, Body}, Acc) ->
    collect_called_modules(Body, Acc);
collect_calls_from_form({function_g, _Line, _Name, _Params, _Guard, Body}, Acc) ->
    collect_called_modules(Body, Acc);
collect_calls_from_form({agent_fn, _Line, _Name, _Params, Body}, Acc) ->
    collect_called_modules(Body, Acc);
collect_calls_from_form({agent_fn_g, _Line, _Name, _Params, _Guard, Body}, Acc) ->
    collect_called_modules(Body, Acc);
collect_calls_from_form({agent_cast_fn, _Line, _Name, _Params, Body}, Acc) ->
    collect_called_modules(Body, Acc);
collect_calls_from_form({call, _Line, _Fun, Args}, Acc) ->
    collect_called_modules(Args, Acc);
collect_calls_from_form({op, _Line, _Op, Lhs, Rhs}, Acc) ->
    Acc1 = collect_calls_from_form(Lhs, Acc),
    collect_calls_from_form(Rhs, Acc1);
collect_calls_from_form({unary, _Line, _Op, Expr}, Acc) ->
    collect_calls_from_form(Expr, Acc);
collect_calls_from_form({assign, _Line, _Pat, Expr}, Acc) ->
    collect_calls_from_form(Expr, Acc);
collect_calls_from_form({if_expr, _Line, Cond, Then, Else}, Acc) ->
    Acc1 = collect_calls_from_form(Cond, Acc),
    Acc2 = collect_called_modules(Then, Acc1),
    collect_called_modules(Else, Acc2);
collect_calls_from_form({pipe, _Line, Lhs, Rhs}, Acc) ->
    Acc1 = collect_calls_from_form(Lhs, Acc),
    collect_calls_from_form(Rhs, Acc1);
collect_calls_from_form({list, _Line, Elems}, Acc) ->
    collect_called_modules(Elems, Acc);
collect_calls_from_form({tuple, _Line, Elems}, Acc) ->
    collect_called_modules(Elems, Acc);
collect_calls_from_form({map, _Line, Pairs}, Acc) ->
    lists:foldl(fun({_K, V}, A) -> collect_calls_from_form(V, A) end, Acc, Pairs);
collect_calls_from_form({switch_expr, _Line, Scrutinee, Clauses}, Acc) ->
    Acc1 = collect_calls_from_form(Scrutinee, Acc),
    lists:foldl(fun(C, A) -> collect_clause_calls(C, A) end, Acc1, Clauses);
collect_calls_from_form({match_block, _Line, Scrutinee, Clauses}, Acc) ->
    Acc1 = collect_calls_from_form(Scrutinee, Acc),
    lists:foldl(fun(C, A) -> collect_clause_calls(C, A) end, Acc1, Clauses);
collect_calls_from_form({try_expr, _Line, Body, Rescues}, Acc) ->
    Acc1 = collect_called_modules(Body, Acc),
    lists:foldl(fun(C, A) -> collect_clause_calls(C, A) end, Acc1, Rescues);
collect_calls_from_form({for_expr, _Line, _Var, Iter, Body}, Acc) ->
    Acc1 = collect_calls_from_form(Iter, Acc),
    collect_called_modules(Body, Acc1);
collect_calls_from_form({block, _Line, _Params, Body}, Acc) ->
    collect_called_modules(Body, Acc);
collect_calls_from_form({field_access, _Line, Expr, _Field}, Acc) ->
    collect_calls_from_form(Expr, Acc);
collect_calls_from_form(_Leaf, Acc) ->
    Acc.

collect_clause_calls({clause, _Line, _Pat, Body}, Acc) ->
    collect_called_modules(Body, Acc);
collect_clause_calls({clause, _Line, _Pat, _Guard, Body}, Acc) ->
    collect_called_modules(Body, Acc);
collect_clause_calls({rescue_clause, _Line, _Pat, Body}, Acc) ->
    collect_called_modules(Body, Acc);
collect_clause_calls(_Other, Acc) ->
    Acc.

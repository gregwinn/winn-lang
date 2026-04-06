%% winn_formatter.erl
%% Code formatter for Winn source files.
%% Parses source → AST, then pretty-prints back to canonical form
%% with comments reinserted by line proximity.

-module(winn_formatter).
-export([format_string/1, format_file/1, check_file/1]).

%% ── Public API ──────────────────────────────────────────────────────────────

format_string(Source) when is_list(Source) ->
    Comments = winn_comment:extract(Source),
    case parse(Source) of
        {ok, AST} ->
            Formatted = format_ast(AST, Comments),
            {ok, Formatted};
        {error, Reason} ->
            {error, Reason}
    end.

format_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} ->
            format_string(binary_to_list(Bin));
        {error, Reason} ->
            {error, {read_error, Reason}}
    end.

check_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} ->
            Source = binary_to_list(Bin),
            case format_string(Source) of
                {ok, Formatted} ->
                    case Formatted =:= Source of
                        true  -> ok;
                        false -> {changed, Path}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, {read_error, Reason}}
    end.

%% ── Parse (lexer → parser only, no transform/codegen) ───────────────────────

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

%% ── Format AST with comment reinsertion ─────────────────────────────────────

format_ast(TopForms, Comments) ->
    {Lines, _LastLine} = format_top_forms(TopForms, 0),
    Merged = merge_comments(Lines, Comments),
    ensure_trailing_newline(lists:flatten(Merged)).

format_top_forms([], _Indent) ->
    {[], 0};
format_top_forms(Forms, Indent) ->
    format_top_forms(Forms, Indent, []).

format_top_forms([], _Indent, Acc) ->
    Lines = lists:reverse(Acc),
    LastLine = case Lines of
        [] -> 0;
        _ -> element(1, lists:last(Lines))
    end,
    {Lines, LastLine};
format_top_forms([Form | Rest], Indent, Acc) ->
    FormLines = format_node(Form, Indent),
    Separator = case Rest of
        [] -> [];
        _  -> [{0, ""}]
    end,
    format_top_forms(Rest, Indent, lists:reverse(FormLines ++ Separator) ++ Acc).

%% ── Node formatting ─────────────────────────────────────────────────────────
%% format_node(Node, Indent) -> [{OrigLine, String}]

%% Module
format_node({module, Line, Name, Body}, Indent) ->
    Header = [{Line, pad(Indent) ++ "module " ++ format_module_name(Name)}],
    BodyLines = format_body(Body, Indent + 2),
    Footer = [{Line, pad(Indent) ++ "end"}],
    Header ++ BodyLines ++ Footer;

%% Agent
format_node({agent, Line, Name, Body}, Indent) ->
    Header = [{Line, pad(Indent) ++ "agent " ++ format_module_name(Name)}],
    BodyLines = format_agent_body(Body, Indent + 2),
    Footer = [{Line, pad(Indent) ++ "end"}],
    Header ++ BodyLines ++ Footer;

%% Function
format_node({function, Line, Name, Params, Body}, Indent) ->
    Sig = pad(Indent) ++ "def " ++ atom_to_list(Name) ++ "(" ++ format_params(Params) ++ ")",
    BodyLines = format_expr_seq(Body, Indent + 2),
    [{Line, Sig}] ++ BodyLines ++ [{Line, pad(Indent) ++ "end"}];

%% Function with guard
format_node({function_g, Line, Name, Params, Guard, Body}, Indent) ->
    Sig = pad(Indent) ++ "def " ++ atom_to_list(Name) ++ "(" ++ format_params(Params) ++ ")"
        ++ " when " ++ format_expr(Guard, Indent + 2),
    BodyLines = format_expr_seq(Body, Indent + 2),
    [{Line, Sig}] ++ BodyLines ++ [{Line, pad(Indent) ++ "end"}];

%% Agent sync function
format_node({agent_fn, Line, Name, Params, Body}, Indent) ->
    Sig = pad(Indent) ++ "def " ++ atom_to_list(Name) ++ "(" ++ format_params(Params) ++ ")",
    BodyLines = format_expr_seq(Body, Indent + 2),
    [{Line, Sig}] ++ BodyLines ++ [{Line, pad(Indent) ++ "end"}];

%% Agent sync function with guard
format_node({agent_fn_g, Line, Name, Params, Guard, Body}, Indent) ->
    Sig = pad(Indent) ++ "def " ++ atom_to_list(Name) ++ "(" ++ format_params(Params) ++ ")"
        ++ " when " ++ format_expr(Guard, Indent + 2),
    BodyLines = format_expr_seq(Body, Indent + 2),
    [{Line, Sig}] ++ BodyLines ++ [{Line, pad(Indent) ++ "end"}];

%% Agent cast (async) function
format_node({agent_cast_fn, Line, Name, Params, Body}, Indent) ->
    Sig = pad(Indent) ++ "async def " ++ atom_to_list(Name) ++ "(" ++ format_params(Params) ++ ")",
    BodyLines = format_expr_seq(Body, Indent + 2),
    [{Line, Sig}] ++ BodyLines ++ [{Line, pad(Indent) ++ "end"}];

%% Agent state declaration
format_node({state_decl, Line, Name, Expr}, Indent) ->
    [{Line, pad(Indent) ++ "state " ++ atom_to_list(Name) ++ " = " ++ format_expr(Expr, Indent)}];

%% Use directive
format_node({use_directive, Line, Mod1, Mod2}, Indent) ->
    [{Line, pad(Indent) ++ "use " ++ format_module_name(Mod1) ++ "." ++ format_module_name(Mod2)}];

%% Import directive
format_node({import_directive, Line, ModName}, Indent) ->
    [{Line, pad(Indent) ++ "import " ++ format_module_name(ModName)}];

%% Alias directive
format_node({alias_directive, Line, Mod1, Mod2}, Indent) ->
    [{Line, pad(Indent) ++ "alias " ++ format_module_name(Mod1) ++ "." ++ format_module_name(Mod2)}];

%% Schema definition
format_node({schema_def, Line, TableName, Fields}, Indent) ->
    Header = [{Line, pad(Indent) ++ "schema \"" ++ binary_to_list(TableName) ++ "\" do"}],
    FieldLines = lists:flatmap(fun(F) -> format_field(F, Indent + 2) end, Fields),
    Footer = [{Line, pad(Indent) ++ "end"}],
    Header ++ FieldLines ++ Footer;

%% Struct definition
format_node({struct_def, Line, Fields}, Indent) ->
    FieldStrs = [[$: | atom_to_list(F)] || F <- Fields],
    [{Line, pad(Indent) ++ "struct [" ++ string:join(FieldStrs, ", ") ++ "]"}];

%% Protocol definition
format_node({protocol_def, Line, Fns}, Indent) ->
    Header = [{Line, pad(Indent) ++ "protocol do"}],
    FnLines = format_body(Fns, Indent + 2),
    Footer = [{Line, pad(Indent) ++ "end"}],
    Header ++ FnLines ++ Footer;

%% Impl definition
format_node({impl_def, Line, ModName, Fns}, Indent) ->
    Header = [{Line, pad(Indent) ++ "impl " ++ format_module_name(ModName) ++ " do"}],
    FnLines = format_body(Fns, Indent + 2),
    Footer = [{Line, pad(Indent) ++ "end"}],
    Header ++ FnLines ++ Footer;

%% Expression nodes — delegate to format_expr and wrap in a line
format_node(Expr, Indent) ->
    Line = node_line(Expr),
    [{Line, pad(Indent) ++ format_expr(Expr, Indent)}].

%% ── Body formatting (with blank lines between items) ────────────────────────

format_body(Items, Indent) ->
    format_body(Items, Indent, []).

format_body([], _Indent, Acc) ->
    lists:reverse(Acc);
format_body([Item | Rest], Indent, Acc) ->
    ItemLines = format_node(Item, Indent),
    Separator = case Rest of
        [] -> [];
        _  -> [{0, ""}]
    end,
    format_body(Rest, Indent, lists:reverse(ItemLines ++ Separator) ++ Acc).

%% Agent body (state decls + functions)
format_agent_body(Items, Indent) ->
    format_agent_body(Items, Indent, []).

format_agent_body([], _Indent, Acc) ->
    lists:reverse(Acc);
format_agent_body([Item | Rest], Indent, Acc) ->
    ItemLines = format_node(Item, Indent),
    Separator = case Rest of
        [] -> [];
        _  -> [{0, ""}]
    end,
    format_agent_body(Rest, Indent, lists:reverse(ItemLines ++ Separator) ++ Acc).

%% ── Expression sequence ─────────────────────────────────────────────────────

format_expr_seq(Exprs, Indent) ->
    lists:flatmap(fun(E) ->
        Line = node_line(E),
        [{Line, pad(Indent) ++ format_expr(E, Indent)}]
    end, Exprs).

%% ── Expression formatting ───────────────────────────────────────────────────
%% format_expr(Node, Indent) -> string()
%% Indent is the current indentation level, used for multi-line constructs.

%% Pipe — flatten and format as chain
format_expr({pipe, _L, _Lhs, _Rhs} = Pipe, Indent) ->
    [First | Stages] = flatten_pipe(Pipe),
    FirstStr = format_expr(First, Indent),
    PipeIndent = pad(Indent + 2),
    StageStrs = [PipeIndent ++ "|> " ++ format_expr(S, Indent + 2) || S <- Stages],
    string:join([FirstStr | StageStrs], "\n");

%% Binary operators
format_expr({op, _L, Op, Lhs, Rhs}, Indent) ->
    LStr = maybe_paren(Lhs, Op, left, Indent),
    RStr = maybe_paren(Rhs, Op, right, Indent),
    LStr ++ " " ++ atom_to_list(Op) ++ " " ++ RStr;

%% Unary operators
format_expr({unary, _L, '-', Expr}, Indent) ->
    "-" ++ format_expr(Expr, Indent);
format_expr({unary, _L, 'not', Expr}, Indent) ->
    "not " ++ format_expr(Expr, Indent);

%% Range
format_expr({range, _L, From, To}, Indent) ->
    format_expr(From, Indent) ++ ".." ++ format_expr(To, Indent);

%% Assignment
format_expr({assign, _L, {var, _, Name}, Expr}, Indent) ->
    atom_to_list(Name) ++ " = " ++ format_expr(Expr, Indent);

%% Pattern assignment
format_expr({pat_assign, _L, Pattern, Expr}, Indent) ->
    format_pattern(Pattern) ++ " = " ++ format_expr(Expr, Indent);

%% State read/write
format_expr({state_read, _L, Name}, _Indent) ->
    "@" ++ atom_to_list(Name);
format_expr({state_write, _L, Name, Expr}, Indent) ->
    "@" ++ atom_to_list(Name) ++ " = " ++ format_expr(Expr, Indent);

%% Field access
format_expr({field_access, _L, Obj, Field}, Indent) ->
    format_expr(Obj, Indent) ++ "." ++ atom_to_list(Field);

%% Local call
format_expr({call, _L, Fun, Args}, Indent) ->
    atom_to_list(Fun) ++ "(" ++ format_args(Args, Indent) ++ ")";

%% Dot call
format_expr({dot_call, _L, Mod, Fun, Args}, Indent) ->
    format_module_name(Mod) ++ "." ++ atom_to_list(Fun) ++ "(" ++ format_args(Args, Indent) ++ ")";

%% Block call
format_expr({block_call, _L, Call, Params, Body}, Indent) ->
    CallStr = format_expr(Call, Indent),
    ParamStr = case Params of
        [] -> "";
        _  -> " |" ++ string:join([atom_to_list(N) || {var, _, N} <- Params], ", ") ++ "|"
    end,
    BodyIndent = Indent + 2,
    case Body of
        [Single] ->
            CallStr ++ " do" ++ ParamStr ++ " " ++ format_expr(Single, BodyIndent) ++ " end";
        Multi ->
            CallStr ++ " do" ++ ParamStr ++ "\n"
            ++ lists:flatten([
                pad(BodyIndent) ++ format_expr(E, BodyIndent) ++ "\n" || E <- Multi
            ])
            ++ pad(Indent) ++ "end"
    end;

%% If/else
format_expr({if_expr, _L, Cond, Then, []}, Indent) ->
    "if " ++ format_expr(Cond, Indent) ++ "\n"
    ++ format_indented_seq(Then, Indent + 2)
    ++ pad(Indent) ++ "end";
format_expr({if_expr, _L, Cond, Then, Else}, Indent) ->
    "if " ++ format_expr(Cond, Indent) ++ "\n"
    ++ format_indented_seq(Then, Indent + 2)
    ++ pad(Indent) ++ "else\n"
    ++ format_indented_seq(Else, Indent + 2)
    ++ pad(Indent) ++ "end";

%% Switch
format_expr({switch_expr, _L, Scrutinee, Clauses}, Indent) ->
    "switch " ++ format_expr(Scrutinee, Indent) ++ "\n"
    ++ lists:flatten([format_switch_clause(C, Indent + 2) || C <- Clauses])
    ++ pad(Indent) ++ "end";

%% Match block
format_expr({match_block, _L, none, Clauses}, Indent) ->
    "match\n"
    ++ lists:flatten([format_match_clause(C, Indent + 2) || C <- Clauses])
    ++ pad(Indent) ++ "end";
format_expr({match_block, _L, Scrutinee, Clauses}, Indent) ->
    "match " ++ format_expr(Scrutinee, Indent) ++ "\n"
    ++ lists:flatten([format_match_clause(C, Indent + 2) || C <- Clauses])
    ++ pad(Indent) ++ "end";

%% Try/rescue
format_expr({try_expr, _L, Body, Rescues}, Indent) ->
    "try\n"
    ++ format_indented_seq(Body, Indent + 2)
    ++ pad(Indent) ++ "rescue\n"
    ++ lists:flatten([format_rescue_clause(C, Indent + 2) || C <- Rescues])
    ++ pad(Indent) ++ "end";

%% For comprehension
format_expr({for_expr, _L, Var, Iter, Body}, Indent) ->
    "for " ++ atom_to_list(Var) ++ " in " ++ format_expr(Iter, Indent) ++ " do\n"
    ++ format_indented_seq(Body, Indent + 2)
    ++ pad(Indent) ++ "end";

%% Anonymous function (lambda)
format_expr({block, _L, Params, Body}, Indent) ->
    ParamStr = format_params(Params),
    case Body of
        [Single] ->
            "fn(" ++ ParamStr ++ ") => " ++ format_expr(Single, Indent) ++ " end";
        Multi ->
            "fn(" ++ ParamStr ++ ") =>\n"
            ++ format_indented_seq(Multi, Indent + 2)
            ++ pad(Indent) ++ "end"
    end;

%% Variables
format_expr({var, _L, Name}, _Indent) ->
    atom_to_list(Name);

%% Atom — could be a module name (PascalCase) or atom literal (:foo)
format_expr({atom, _L, Name}, _Indent) ->
    Str = atom_to_list(Name),
    case Str of
        [C | _] when C >= $A, C =< $Z -> format_module_name(Name);
        _ -> ":" ++ Str
    end;

%% Literals
format_expr({integer, _L, Val}, _Indent) ->
    integer_to_list(Val);
format_expr({float, _L, Val}, _Indent) ->
    float_to_list(Val, [{decimals, 10}, compact]);
format_expr({string, _L, Val}, _Indent) when is_binary(Val) ->
    "\"" ++ escape_string(binary_to_list(Val)) ++ "\"";
format_expr({boolean, _L, true}, _Indent) ->
    "true";
format_expr({boolean, _L, false}, _Indent) ->
    "false";
format_expr({nil, _L}, _Indent) ->
    "nil";

%% Interpolated string
format_expr({interp_string, _L, Parts}, _Indent) ->
    "\"" ++ lists:flatten([format_interp_part(P) || P <- Parts]) ++ "\"";

%% List
format_expr({list, _L, Elems}, Indent) ->
    "[" ++ format_args(Elems, Indent) ++ "]";

%% Tuple
format_expr({tuple, _L, Elems}, Indent) ->
    "{" ++ format_args(Elems, Indent) ++ "}";

%% Map
format_expr({map, _L, []}, _Indent) ->
    "%{}";
format_expr({map, _L, Pairs}, Indent) ->
    PairStrs = [format_map_pair(P, Indent) || P <- Pairs],
    "%{" ++ string:join(PairStrs, ", ") ++ "}";

%% Catch-all
format_expr(Other, _Indent) ->
    lists:flatten(io_lib:format("~p", [Other])).

%% ── Helpers ─────────────────────────────────────────────────────────────────

format_module_name(Name) when is_atom(Name) ->
    Raw = atom_to_list(Name),
    case lists:member($., Raw) of
        true ->
            Parts = string:split(Raw, ".", all),
            string:join([capitalize(P) || P <- Parts], ".");
        false ->
            capitalize(Raw)
    end.

capitalize([]) -> [];
capitalize([C | Rest]) when C >= $a, C =< $z -> [C - 32 | Rest];
capitalize(S) -> S.

format_params(Params) ->
    string:join([format_pattern(P) || P <- Params], ", ").

format_args(Args, Indent) ->
    string:join([format_expr(A, Indent) || A <- Args], ", ").

format_pattern({var, _L, Name}) ->
    atom_to_list(Name);
format_pattern({pat_wildcard, _L}) ->
    "_";
format_pattern({pat_atom, _L, true}) ->
    "true";
format_pattern({pat_atom, _L, false}) ->
    "false";
format_pattern({pat_atom, _L, nil}) ->
    "nil";
format_pattern({pat_atom, _L, Val}) ->
    ":" ++ atom_to_list(Val);
format_pattern({pat_integer, _L, Val}) ->
    integer_to_list(Val);
format_pattern({pat_tuple, _L, Elems}) ->
    "{" ++ string:join([format_pattern(E) || E <- Elems], ", ") ++ "}";
format_pattern({pat_list, _L, Elems, nil}) ->
    "[" ++ string:join([format_pattern(E) || E <- Elems], ", ") ++ "]";
format_pattern({pat_list, _L, Elems, Tail}) ->
    "[" ++ string:join([format_pattern(E) || E <- Elems], ", ")
    ++ " | " ++ format_pattern(Tail) ++ "]";
format_pattern({default_param, _L, Name, Val}) ->
    atom_to_list(Name) ++ " = " ++ format_expr(Val, 0);
format_pattern({tuple, _L, Elems}) ->
    "{" ++ string:join([format_pattern(E) || E <- Elems], ", ") ++ "}";
format_pattern({atom, _L, Val}) ->
    ":" ++ atom_to_list(Val);
format_pattern({integer, _L, Val}) ->
    integer_to_list(Val);
format_pattern({boolean, _L, Val}) ->
    atom_to_list(Val);
format_pattern(Other) ->
    format_expr(Other, 0).

format_map_pair({Key, Val}, Indent) ->
    atom_to_list(Key) ++ ": " ++ format_expr(Val, Indent).

format_interp_part({str, Bin}) when is_binary(Bin) ->
    escape_string(binary_to_list(Bin));
format_interp_part({expr, ExprStr}) when is_list(ExprStr) ->
    "#{" ++ ExprStr ++ "}".

format_switch_clause({switch_clause, _L, Pattern, none, Body}, Indent) ->
    case Body of
        [Single] ->
            pad(Indent) ++ format_pattern(Pattern) ++ " => " ++ format_expr(Single, Indent) ++ "\n";
        Multi ->
            pad(Indent) ++ format_pattern(Pattern) ++ " => do\n"
            ++ format_indented_seq(Multi, Indent + 2)
            ++ pad(Indent) ++ "end\n"
    end;
format_switch_clause({switch_clause, _L, Pattern, Guard, Body}, Indent) ->
    GuardStr = " when " ++ format_expr(Guard, Indent),
    case Body of
        [Single] ->
            pad(Indent) ++ format_pattern(Pattern) ++ GuardStr ++ " => " ++ format_expr(Single, Indent) ++ "\n";
        Multi ->
            pad(Indent) ++ format_pattern(Pattern) ++ GuardStr ++ " => do\n"
            ++ format_indented_seq(Multi, Indent + 2)
            ++ pad(Indent) ++ "end\n"
    end.

format_match_clause({match_clause, _L, Tag, Pattern, Body}, Indent) ->
    TagStr = atom_to_list(Tag),
    case Body of
        [Single] ->
            pad(Indent) ++ TagStr ++ " " ++ format_pattern(Pattern) ++ " => " ++ format_expr(Single, Indent) ++ "\n";
        Multi ->
            pad(Indent) ++ TagStr ++ " " ++ format_pattern(Pattern) ++ " =>\n"
            ++ format_indented_seq(Multi, Indent + 2)
    end.

format_rescue_clause({rescue_clause, _L, Pattern, Body}, Indent) ->
    case Body of
        [Single] ->
            pad(Indent) ++ format_pattern(Pattern) ++ " => " ++ format_expr(Single, Indent) ++ "\n";
        Multi ->
            pad(Indent) ++ format_pattern(Pattern) ++ " => do\n"
            ++ format_indented_seq(Multi, Indent + 2)
            ++ pad(Indent) ++ "end\n"
    end.

format_indented_seq(Exprs, Indent) ->
    lists:flatten([pad(Indent) ++ format_expr(E, Indent) ++ "\n" || E <- Exprs]).

format_field({field, Line, Name, Type}, Indent) ->
    [{Line, pad(Indent) ++ "field :" ++ atom_to_list(Name) ++ ", :" ++ atom_to_list(Type)}].

%% ── Pipe flattening ─────────────────────────────────────────────────────────

flatten_pipe({pipe, _L, Lhs, Rhs}) ->
    flatten_pipe(Lhs) ++ [Rhs];
flatten_pipe(Other) ->
    [Other].

%% ── Operator precedence for parenthesization ────────────────────────────────

precedence('|>') -> 1;
precedence('or') -> 2;
precedence('and') -> 3;
precedence('==') -> 4;
precedence('!=') -> 4;
precedence('<') -> 4;
precedence('>') -> 4;
precedence('<=') -> 4;
precedence('>=') -> 4;
precedence('+') -> 5;
precedence('-') -> 5;
precedence('<>') -> 5;
precedence('*') -> 6;
precedence('/') -> 6;
precedence(_) -> 99.

maybe_paren({op, _, ChildOp, _, _} = Expr, ParentOp, _Side, Indent) ->
    case precedence(ChildOp) < precedence(ParentOp) of
        true  -> "(" ++ format_expr(Expr, Indent) ++ ")";
        false -> format_expr(Expr, Indent)
    end;
maybe_paren(Expr, _ParentOp, _Side, Indent) ->
    format_expr(Expr, Indent).

%% ── Comment merging ─────────────────────────────────────────────────────────

merge_comments(CodeLines, []) ->
    [Text ++ "\n" || {_L, Text} <- CodeLines];
merge_comments(CodeLines, Comments) ->
    merge_comments(CodeLines, lists:keysort(1, Comments), []).

merge_comments([], [], Acc) ->
    lists:reverse(Acc);
merge_comments([], [{_CLine, CText, _Type} | RestC], Acc) ->
    merge_comments([], RestC, [CText ++ "\n" | Acc]);
merge_comments([{CodeLine, Text} | RestCode], Comments, Acc) ->
    {Before, After} = lists:partition(
        fun({CLine, _CText, _Type}) -> CLine < CodeLine andalso CodeLine > 0 end,
        Comments
    ),
    Ind = count_leading_spaces(Text),
    CommentLines = [pad(Ind) ++ CText ++ "\n" || {_CL, CText, _CT} <- Before],
    merge_comments(RestCode, After, [Text ++ "\n" | CommentLines] ++ Acc);
merge_comments([], Comments, Acc) ->
    Remaining = [CText ++ "\n" || {_CL, CText, _CT} <- Comments],
    lists:reverse(Acc) ++ Remaining.

count_leading_spaces([$\s | Rest]) -> 1 + count_leading_spaces(Rest);
count_leading_spaces(_) -> 0.

%% ── Utility ─────────────────────────────────────────────────────────────────

pad(0) -> "";
pad(N) when N > 0 -> lists:duplicate(N, $\s).

escape_string([]) -> [];
escape_string([$\n | Rest]) -> "\\n" ++ escape_string(Rest);
escape_string([$\t | Rest]) -> "\\t" ++ escape_string(Rest);
escape_string([$\r | Rest]) -> "\\r" ++ escape_string(Rest);
escape_string([$\\ | Rest]) -> "\\\\" ++ escape_string(Rest);
escape_string([$" | Rest]) -> "\\\"" ++ escape_string(Rest);
escape_string([C | Rest]) -> [C | escape_string(Rest)].

node_line({_, L, _}) when is_integer(L) -> L;
node_line({_, L, _, _}) when is_integer(L) -> L;
node_line({_, L, _, _, _}) when is_integer(L) -> L;
node_line({_, L, _, _, _, _}) when is_integer(L) -> L;
node_line({_, L}) when is_integer(L) -> L;
node_line(_) -> 0.

ensure_trailing_newline([]) -> "\n";
ensure_trailing_newline(Str) ->
    case lists:last(Str) of
        $\n -> Str;
        _   -> Str ++ "\n"
    end.

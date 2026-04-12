%% winn_docs.erl
%% Documentation generator: extracts doc comments from source files,
%% generates Markdown API docs with a Mermaid module dependency graph.

-module(winn_docs).
-export([generate/2, generate_module_doc/1, generate_module_doc_from_string/1,
         generate_index/2]).

%% ── Public API ───────────────────────────────────────────────────────────────

-spec generate([string()], string()) -> ok | {error, term()}.
generate(Files, OutDir) ->
    ok = filelib:ensure_path(OutDir),
    Results = [generate_module_doc(F) || F <- Files],
    Good = [R || {ok, R} <- Results],

    %% Write per-module docs
    lists:foreach(fun({ModName, Markdown, _Deps}) ->
        FileName = string:lowercase(atom_to_list(ModName)) ++ ".md",
        FilePath = filename:join(OutDir, FileName),
        file:write_file(FilePath, Markdown)
    end, Good),

    %% Build dependency graph and write index
    AllDeps = lists:flatmap(fun({_, _, Deps}) -> Deps end, Good),
    ModNames = [M || {M, _, _} <- Good],
    Index = generate_index(ModNames, AllDeps),
    file:write_file(filename:join(OutDir, "index.md"), Index),

    io:format("Generated docs for ~B module(s) in ~s/~n", [length(Good), OutDir]),
    ok.

%% ── Per-module doc generation ────────────────────────────────────────────────

-spec generate_module_doc(string()) -> {ok, {atom(), binary(), [{atom(), atom()}]}} | {error, term()}.
generate_module_doc(FilePath) ->
    case file:read_file(FilePath) of
        {ok, Bin} ->
            Source = binary_to_list(Bin),
            Lines = string:split(Source, "\n", all),
            case parse_source(Source) of
                {ok, AST} ->
                    [{module, _L, ModName, Body}|_] = AST,
                    ModDoc = extract_module_doc(Lines, Body),
                    Fns = extract_functions(Lines, Body),
                    Deps = extract_deps(ModName, Body),
                    Markdown = format_module(ModName, ModDoc, Fns),
                    {ok, {ModName, Markdown, Deps}};
                {error, Reason} ->
                    io:format("Warning: could not parse ~s: ~p~n", [FilePath, Reason]),
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% For testing: generate docs from a source string instead of a file.
generate_module_doc_from_string(Source) ->
    Lines = string:split(Source, "\n", all),
    case parse_source(Source) of
        {ok, AST} ->
            [{module, _L, ModName, Body}|_] = AST,
            ModDoc = extract_module_doc(Lines, Body),
            Fns = extract_functions(Lines, Body),
            Deps = extract_deps(ModName, Body),
            Markdown = format_module(ModName, ModDoc, Fns),
            {ok, {ModName, Markdown, Deps}};
        {error, Reason} ->
            {error, Reason}
    end.

parse_source(Source) ->
    case winn_lexer:string(Source) of
        {ok, RawTokens, _} ->
            Tokens = winn_newline_filter:filter(RawTokens),
            case winn_parser:parse(Tokens) of
                {ok, AST} -> {ok, AST};
                {error, R} -> {error, R}
            end;
        {error, R, _} -> {error, R}
    end.

%% ── Comment extraction ──────────────────────────────────────────────────────

extract_module_doc(Lines, _Body) ->
    %% Module doc = contiguous comment block immediately after module line.
    %% Stops at the first blank or non-comment line.
    collect_module_comments(Lines, 2, []).

collect_module_comments(Lines, N, Acc) when N > length(Lines) -> lists:reverse(Acc);
collect_module_comments(Lines, N, Acc) ->
    Line = lists:nth(N, Lines),
    Trimmed = string:trim(Line, leading),
    case Trimmed of
        [$# | Rest] ->
            Comment = list_to_binary(string:trim(Rest, leading, " ")),
            collect_module_comments(Lines, N + 1, [Comment | Acc]);
        [] when Acc =:= [] ->
            %% Skip leading blank lines after module declaration
            collect_module_comments(Lines, N + 1, Acc);
        _ ->
            lists:reverse(Acc)
    end.

extract_functions(Lines, Body) ->
    %% Get all function definitions with their line numbers.
    %% We intentionally only match the public `function` tag, not
    %% `private_function` — privates are excluded from generated docs.
    RawFns = [{Name, Params, L} || {function, L, Name, Params, _} <- Body],
    %% Group by name (multi-clause functions)
    Grouped = group_functions(RawFns),
    %% Extract doc comments for each function group
    [{Name, Params, extract_comments_before(Lines, FirstLine)}
     || {Name, Params, FirstLine} <- Grouped].

group_functions([]) -> [];
group_functions([{Name, Params, Line} | Rest]) ->
    {Same, Others} = lists:partition(fun({N, _, _}) -> N =:= Name end, Rest),
    AllParams = [Params | [P || {_, P, _} <- Same]],
    [{Name, AllParams, Line} | group_functions(Others)].

extract_comments_before(_Lines, TargetLine) when TargetLine =< 1 -> [];
extract_comments_before(Lines, TargetLine) ->
    collect_comments(Lines, TargetLine - 1, []).

collect_comments(_Lines, 0, Acc) -> Acc;
collect_comments(Lines, LineNum, Acc) ->
    Line = lists:nth(LineNum, Lines),
    Trimmed = string:trim(Line, leading),
    case Trimmed of
        [$# | Rest] ->
            Comment = string:trim(Rest, leading, " "),
            collect_comments(Lines, LineNum - 1, [list_to_binary(Comment) | Acc]);
        _ ->
            %% Blank or non-comment line — stop collecting
            Acc
    end.

extract_comment_range(_Lines, From, To) when From > To -> [];
extract_comment_range(Lines, From, To) ->
    CommentLines = lists:filtermap(fun(N) ->
        Line = lists:nth(N, Lines),
        Trimmed = string:trim(Line, leading),
        case Trimmed of
            [$# | Rest] -> {true, list_to_binary(string:trim(Rest, leading, " "))};
            _ -> false
        end
    end, lists:seq(From, min(To, length(Lines)))),
    CommentLines.

%% ── Dependency extraction ───────────────────────────────────────────────────

-define(STDLIB_MODULES, ['IO', 'String', 'Enum', 'List', 'Map', 'System',
    'UUID', 'DateTime', 'Logger', 'Crypto', 'JSON', 'GenServer', 'Supervisor',
    'Winn', 'Server', 'Repo', 'Changeset']).

extract_deps(ModName, Body) ->
    DotCalls = collect_dot_calls(Body),
    UseDeps  = [{ModName, list_to_atom(atom_to_list(Top) ++ "." ++ atom_to_list(Sub))}
                || {use_directive, _, Top, Sub} <- Body,
                   not lists:member(Top, ['Winn'])],
    AllDeps = [{ModName, Mod} || Mod <- DotCalls] ++ UseDeps,
    lists:usort(AllDeps).

collect_dot_calls(Body) when is_list(Body) ->
    lists:flatmap(fun collect_dot_calls/1, Body);
collect_dot_calls({dot_call, _, Mod, _, Args}) ->
    case lists:member(Mod, ?STDLIB_MODULES) of
        true  -> collect_dot_calls(Args);
        false -> [Mod | collect_dot_calls(Args)]
    end;
collect_dot_calls(Tuple) when is_tuple(Tuple) ->
    collect_dot_calls(tuple_to_list(Tuple));
collect_dot_calls(_) -> [].

%% ── Markdown formatting ─────────────────────────────────────────────────────

format_module(ModName, ModDoc, Functions) ->
    Header = iolist_to_binary([<<"# ">>, atom_to_binary(ModName), <<"\n">>]),
    DocSection = case ModDoc of
        [] -> <<"\n">>;
        _ -> iolist_to_binary([<<"\n">>, lists:join(<<"\n">>, ModDoc), <<"\n\n">>])
    end,
    FnSections = [format_function(Name, ParamSets, Doc) || {Name, ParamSets, Doc} <- Functions],
    iolist_to_binary([Header, DocSection, lists:join(<<"\n">>, FnSections)]).

format_function(Name, ParamSets, DocLines) ->
    %% Show first param set in the header
    FirstParams = hd(ParamSets),
    ParamStr = format_params(FirstParams),
    Header = iolist_to_binary([
        <<"## `">>, atom_to_binary(Name), <<"(">>, ParamStr, <<")`\n">>
    ]),
    %% Show additional clauses if multi-clause
    Clauses = case length(ParamSets) > 1 of
        true ->
            Extra = [iolist_to_binary([
                <<"- `">>, atom_to_binary(Name), <<"(">>, format_params(P), <<")`\n">>
            ]) || P <- tl(ParamSets)],
            iolist_to_binary([<<"\nAlso:\n">> | Extra]);
        false -> <<>>
    end,
    Doc = case DocLines of
        [] -> <<"\n">>;
        _  -> iolist_to_binary([<<"\n">>, lists:join(<<"\n">>, DocLines), <<"\n\n">>])
    end,
    iolist_to_binary([Header, Doc, Clauses]).

format_params(Params) ->
    ParamStrs = [format_param(P) || P <- Params],
    list_to_binary(lists:join(", ", ParamStrs)).

format_param({var, _, Name}) -> atom_to_binary(Name);
format_param({pat_atom, _, Val}) -> iolist_to_binary([<<":" >>, atom_to_binary(Val)]);
format_param({pat_var, _, Name}) -> atom_to_binary(Name);
format_param({pat_wildcard, _}) -> <<"_">>;
format_param({pat_tuple, _, Elems}) ->
    Inner = lists:join(<<", ">>, [format_param(E) || E <- Elems]),
    iolist_to_binary([<<"{">>, Inner, <<"}">>]);
format_param(_) -> <<"...">>.

%% ── Index + Mermaid graph ───────────────────────────────────────────────────

generate_index(ModNames, DepEdges) ->
    Header = <<"# API Documentation\n\n">>,

    %% Module list
    ModList = iolist_to_binary([
        <<"## Modules\n\n">>,
        [iolist_to_binary([
            <<"- [">>, atom_to_binary(M), <<"](">>,
            list_to_binary(string:lowercase(atom_to_list(M))),
            <<".md)\n">>
        ]) || M <- lists:sort(ModNames)]
    ]),

    %% Mermaid dependency graph
    Graph = case DepEdges of
        [] -> <<>>;
        _ ->
            Edges = lists:usort(DepEdges),
            MermaidLines = [iolist_to_binary([
                <<"  ">>, atom_to_binary(From), <<" --> ">>, atom_to_binary(To)
            ]) || {From, To} <- Edges],
            iolist_to_binary([
                <<"\n## Module Dependencies\n\n">>,
                <<"```mermaid\ngraph TD\n">>,
                lists:join(<<"\n">>, MermaidLines),
                <<"\n```\n">>
            ])
    end,

    iolist_to_binary([Header, ModList, Graph]).

%% winn.erl
%% Public API for the Winn compiler.
%%
%% Pipeline:
%%   1. winn_lexer    — tokenise source
%%   2. winn_parser   — parse tokens into AST
%%   3. winn_semantic — analyse AST (scope, types)
%%   4. winn_transform — desugar (pipes, match blocks, etc.)
%%   5. winn_codegen  — generate Core Erlang
%%   6. winn_core_emit — compile Core Erlang to .beam

-module(winn).
-export([
    compile_file/1,
    compile_file/2,
    compile_string/2,
    compile_string/3
]).

%% Default output directory.
-define(DEFAULT_OUTDIR, ".").

%% Compile a .winn file, writing .beam to the same directory.
compile_file(Path) ->
    compile_file(Path, filename:dirname(Path)).

%% Compile a .winn file, writing .beam to OutDir.
compile_file(Path, OutDir) ->
    case file:read_file(Path) of
        {ok, Binary} ->
            Source = binary_to_list(Binary),
            compile_string(Source, Path, OutDir);
        {error, Reason} ->
            Err = {error, {file_read, Path, Reason}},
            print_error(Err, "", Path),
            Err
    end.

%% Compile a source string (FileName used for error messages).
compile_string(Source, FileName) ->
    compile_string(Source, FileName, ?DEFAULT_OUTDIR).

compile_string(Source, FileName, OutDir) ->
    case run_pipeline(Source, FileName, OutDir) of
        {ok, BeamFiles} ->
            {ok, BeamFiles};
        {error, _} = Err ->
            print_error(Err, Source, FileName),
            Err
    end.

%% ── Internal pipeline ─────────────────────────────────────────────────────

run_pipeline(Source, FileName, OutDir) ->
    with([
        fun() -> lex(Source, FileName) end,
        fun(Tokens)  -> parse(Tokens, FileName) end,
        fun(Forms)   -> semantic(Forms, Source, FileName) end,
        fun(Forms)   -> transform(Forms, FileName) end,
        fun(Forms)   -> codegen(Forms, FileName) end,
        fun(CoreMods) -> emit(CoreMods, OutDir, FileName) end
    ]).

%% ── Pipeline stages ───────────────────────────────────────────────────────

lex(Source, FileName) ->
    case winn_lexer:string(Source) of
        {ok, RawTokens, _EndLine} ->
            {ok, winn_newline_filter:filter(RawTokens)};
        {error, {Line, winn_lexer, Error}, _} ->
            {error, {lex_error, FileName, Line, winn_lexer:format_error(Error)}}
    end.

parse(Tokens, FileName) ->
    case winn_parser:parse(Tokens) of
        {ok, Forms} ->
            {ok, Forms};
        {error, {Line, winn_parser, Msg}} ->
            {error, {parse_error, FileName, Line, Msg}}
    end.

semantic(Forms, Source, FileName) ->
    case winn_semantic:analyse(Forms) of
        {ok, Analysed} ->
            {ok, Analysed};
        {error, Errors} ->
            Fatals = [E || E <- Errors, element(1, E) =:= error],
            %% Print all diagnostics with nice formatting.
            Formatted = winn_errors:format_diagnostics(Errors, Source, FileName),
            io:put_chars(standard_error, Formatted),
            case Fatals of
                [] -> {ok, Forms};
                _  -> {error, {semantic_errors, Errors}}
            end
    end.

transform(Forms, FileName) ->
    try
        {ok, winn_transform:transform(Forms)}
    catch
        error:{unsupported_pipe_block_target, Line} ->
            {error, {transform_error, FileName, Line,
                     <<"Unsupported Pipe Target">>,
                     <<"The right side of |> must be a function call.">>}};
        error:{unsupported_block_call_target, Line} ->
            {error, {transform_error, FileName, Line,
                     <<"Unsupported Block Target">>,
                     <<"A do...end block must follow a function call.">>}};
        error:Reason ->
            Line = extract_line(Reason),
            {error, {transform_error, FileName, Line,
                     <<"Transform Error">>,
                     iolist_to_binary(io_lib:format("~p", [Reason]))}}
    end.

codegen(Forms, FileName) ->
    try
        {ok, winn_codegen:gen(Forms)}
    catch
        error:{unsupported_ast_node, Node} ->
            Line = extract_line(Node),
            {error, {codegen_error, FileName, Line,
                     <<"Unsupported Expression">>,
                     <<"The compiler cannot translate this expression.">>}};
        error:{unsupported_pattern_node, Node} ->
            Line = extract_line(Node),
            {error, {codegen_error, FileName, Line,
                     <<"Unsupported Pattern">>,
                     <<"This pattern syntax is not supported.">>}};
        error:Reason ->
            Line = extract_line(Reason),
            {error, {codegen_error, FileName, Line,
                     <<"Code Generation Error">>,
                     iolist_to_binary(io_lib:format("~p", [Reason]))}}
    end.

emit(CoreMods, OutDir, FileName) ->
    Results = [winn_core_emit:emit(Mod, OutDir) || Mod <- CoreMods],
    Errors  = [E || {error, E} <- Results],
    case Errors of
        [] ->
            BeamFiles = [F || {ok, F} <- Results],
            {ok, BeamFiles};
        _ ->
            {error, {compile_failed, Errors}}
    end.

%% ── Helpers ─────────────────────────────────────────────────────────────

with([F | Rest]) ->
    case F() of
        {ok, Value} -> with(Rest, Value);
        {error, _} = Err -> Err
    end.

with([], Value) ->
    {ok, Value};
with([F | Rest], Value) ->
    case F(Value) of
        {ok, Next}  -> with(Rest, Next);
        {error, _} = Err -> Err
    end.

print_error({error, Reason}, Source, FileName) ->
    Formatted = winn_errors:format(Reason, Source, FileName),
    io:put_chars(standard_error, Formatted);
print_error(_, _, _) ->
    ok.

extract_line(Term) when is_tuple(Term), tuple_size(Term) >= 2 ->
    case element(2, Term) of
        L when is_integer(L) -> L;
        _ -> none
    end;
extract_line(_) -> none.

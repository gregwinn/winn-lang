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
            format_error({file_read, Path, Reason})
    end.

%% Compile a source string (FileName used for error messages).
compile_string(Source, FileName) ->
    compile_string(Source, FileName, ?DEFAULT_OUTDIR).

compile_string(Source, FileName, OutDir) ->
    case run_pipeline(Source, FileName, OutDir) of
        {ok, BeamFiles} ->
            io:format("Compiled ~s → ~s~n",
                      [FileName, lists:join(", ", BeamFiles)]),
            {ok, BeamFiles};
        {error, _} = Err ->
            Err
    end.

%% ── Internal pipeline ─────────────────────────────────────────────────────

run_pipeline(Source, FileName, OutDir) ->
    with([
        fun() -> lex(Source, FileName) end,
        fun(Tokens)  -> parse(Tokens, FileName) end,
        fun(Forms)   -> semantic(Forms) end,
        fun(Forms)   -> transform(Forms) end,
        fun(Forms)   -> codegen(Forms) end,
        fun(CoreMods) -> emit(CoreMods, OutDir) end
    ]).

%% ── Pipeline stages ───────────────────────────────────────────────────────

lex(Source, FileName) ->
    case winn_lexer:string(Source) of
        {ok, Tokens, _EndLine} ->
            {ok, Tokens};
        {error, {Line, winn_lexer, Error}, _} ->
            format_error({lex_error, FileName, Line, winn_lexer:format_error(Error)})
    end.

parse(Tokens, FileName) ->
    case winn_parser:parse(Tokens) of
        {ok, Forms} ->
            {ok, Forms};
        {error, {Line, winn_parser, Msg}} ->
            format_error({parse_error, FileName, Line, Msg})
    end.

semantic(Forms) ->
    case winn_semantic:analyse(Forms) of
        {ok, Analysed} ->
            {ok, Analysed};
        {error, Errors} ->
            %% Print warnings/errors but continue if only warnings.
            Fatals = [E || E <- Errors, element(1, E) =:= error],
            [print_diagnostic(E) || E <- Errors],
            case Fatals of
                [] -> {ok, Forms};
                _  -> {error, Errors}
            end
    end.

transform(Forms) ->
    {ok, winn_transform:transform(Forms)}.

codegen(Forms) ->
    CoreMods = winn_codegen:gen(Forms),
    {ok, CoreMods}.

emit(CoreMods, OutDir) ->
    Results = [winn_core_emit:emit(Mod, OutDir) || Mod <- CoreMods],
    Errors  = [E || {error, E} <- Results],
    case Errors of
        [] ->
            BeamFiles = [F || {ok, F} <- Results],
            {ok, BeamFiles};
        _ ->
            format_error({emit_errors, Errors})
    end.

%% ── Helpers ───────────────────────────────────────────────────────────────

%% Chain a list of fun() | fun(Acc) steps, threading the result.
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

format_error(Reason) ->
    {error, Reason}.

print_diagnostic({warning, Line, Name, Msg}) ->
    io:format("warning: line ~p (~p): ~s~n", [Line, Name, Msg]);
print_diagnostic({error, Line, Name, Msg}) ->
    io:format("error: line ~p (~p): ~s~n", [Line, Name, Msg]);
print_diagnostic(Other) ->
    io:format("diagnostic: ~p~n", [Other]).

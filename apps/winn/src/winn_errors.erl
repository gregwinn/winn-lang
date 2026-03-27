%% winn_errors.erl
%% Human-readable compiler error formatting for Winn.
%%
%% Produces Elm/Rust-style error output:
%%
%%   ── Syntax Error ──────────────────────── src/app.winn ──
%%
%%     14 |   x = compute()
%%     15 |   end end
%%              ^^^
%%   Unexpected 'end'. Expected an expression.
%%

-module(winn_errors).
-export([format/3, format_diagnostics/3, set_color/1]).

-record(diag, {
    severity  = error :: error | warning,
    title     = <<>>  :: binary(),
    file      = ""    :: string(),
    line      = none  :: integer() | none,
    col       = none  :: integer() | none,
    span_len  = none  :: integer() | none,
    message   = <<>>  :: binary(),
    hint      = none  :: binary() | none
}).

-define(WIDTH, 60).

%% ── Public API ──────────────────────────────────────────────────────────

set_color(Bool) ->
    put(winn_color, Bool), ok.

%% Format a single error term with source context.
format(Error, Source, FileName) ->
    Diags = normalize(Error, Source, FileName),
    Lines = source_lines(Source),
    unicode:characters_to_binary([render(D, Lines) || D <- Diags]).

%% Format a list of semantic diagnostics.
format_diagnostics(DiagList, Source, FileName) ->
    Lines = source_lines(Source),
    Diags = [normalize_semantic(D, FileName) || D <- DiagList],
    unicode:characters_to_binary([render(D, Lines) || D <- Diags]).

%% ── Normalization ───────────────────────────────────────────────────────

normalize({lex_error, File, Line, Msg}, _Source, _FileName) ->
    [#diag{
        severity = error,
        title    = <<"Illegal Character">>,
        file     = File,
        line     = Line,
        message  = unicode:characters_to_binary(["Unexpected character: ", Msg, "."])
    }];

normalize({parse_error, File, Line, RawMsg}, Source, _FileName) ->
    Token = extract_parser_token(RawMsg),
    Col = find_token_col(Token, get_source_line(Source, Line)),
    [#diag{
        severity = error,
        title    = <<"Syntax Error">>,
        file     = File,
        line     = Line,
        col      = Col,
        span_len = length(Token),
        message  = unicode:characters_to_binary(["Unexpected ", quote(Token), "."]),
        hint     = suggest_parse_fix(Token)
    }];

normalize({semantic_errors, Errors}, _Source, FileName) ->
    [normalize_semantic(E, FileName) || E <- Errors];

normalize({transform_error, File, Line, Title, Msg}, _Source, _FileName) ->
    [#diag{
        severity = error,
        title    = Title,
        file     = File,
        line     = Line,
        message  = Msg
    }];

normalize({codegen_error, File, Line, Title, Msg}, _Source, _FileName) ->
    [#diag{
        severity = error,
        title    = Title,
        file     = File,
        line     = Line,
        message  = Msg
    }];

normalize({emit_errors, ErrorList}, _Source, FileName) ->
    lists:flatmap(fun({_Mod, Errs}) ->
        [normalize_core_error(E, FileName) || E <- Errs]
    end, ErrorList);

normalize({compile_failed, ErrorList}, _Source, FileName) ->
    lists:flatmap(fun({_Mod, Errs}) ->
        [normalize_core_error(E, FileName) || E <- Errs]
    end, ErrorList);

normalize({file_read, Path, Reason}, _Source, _FileName) ->
    [#diag{
        severity = error,
        title    = <<"File Error">>,
        file     = Path,
        message  = unicode:characters_to_binary(io_lib:format("Cannot read file: ~p", [Reason]))
    }];

normalize(Other, _Source, FileName) ->
    [#diag{
        severity = error,
        title    = <<"Compilation Error">>,
        file     = FileName,
        message  = unicode:characters_to_binary(io_lib:format("~p", [Other]))
    }].

normalize_semantic({Sev, Line, _Name, Msg}, File) ->
    Title = case Sev of
        error   -> <<"Error">>;
        warning -> <<"Warning">>
    end,
    #diag{
        severity = Sev,
        title    = Title,
        file     = File,
        line     = Line,
        message  = unicode:characters_to_binary(Msg)
    }.

normalize_core_error({none, core_lint, {unbound_var, Var, {Fun, Arity}}}, File) ->
    VarStr = atom_to_list(Var),
    %% Core Erlang capitalizes vars; show the Winn name (lowercase first char).
    WinnVar = case VarStr of
        [C | Rest] when C >= $A, C =< $Z -> [(C + 32) | Rest];
        _ -> VarStr
    end,
    #diag{
        severity = error,
        title    = <<"Undefined Variable">>,
        file     = File,
        message  = unicode:characters_to_binary(io_lib:format(
            "Variable '~s' is not defined in function ~s/~B.",
            [WinnVar, Fun, Arity]))
    };
normalize_core_error({Line, Mod, Desc}, File) ->
    #diag{
        severity = error,
        title    = <<"Compile Error">>,
        file     = File,
        line     = case Line of none -> none; L when is_integer(L) -> L; _ -> none end,
        message  = unicode:characters_to_binary(io_lib:format("~s", [Mod:format_error(Desc)]))
    };
normalize_core_error(Other, File) ->
    #diag{
        severity = error,
        title    = <<"Compile Error">>,
        file     = File,
        message  = unicode:characters_to_binary(io_lib:format("~p", [Other]))
    }.

%% ── Rendering ───────────────────────────────────────────────────────────

render(#diag{} = D, Lines) ->
    [
        $\n,
        render_header(D),
        $\n,
        render_source_context(D, Lines),
        render_message(D),
        $\n
    ].

render_header(#diag{severity = Sev, title = Title, file = File}) ->
    TitleStr = [" ", binary_to_list(Title), " "],
    FileStr  = [" ", File, " "],
    TitleLen = iol_size(TitleStr),
    FileLen  = iol_size(FileStr),
    FillLen  = max(2, ?WIDTH - 2 - TitleLen - 2 - FileLen - 2),
    Fill     = lists:duplicate(FillLen, $-),
    Bar = ["──", TitleStr, Fill, FileStr, "──"],
    case Sev of
        error   -> [bold(red(Bar)), $\n];
        warning -> [bold(yellow(Bar)), $\n]
    end.

render_source_context(#diag{line = none}, _Lines) ->
    [];
render_source_context(#diag{line = Line, col = Col, span_len = SpanLen, severity = Sev}, Lines) ->
    %% Show up to 1 line before and after for context.
    Gutter = gutter_width(Line + 1),
    Context = lists:flatten([
        render_context_line(Line - 1, Lines, Gutter),
        render_error_line(Line, Lines, Gutter, Sev),
        render_caret_line(Line, Lines, Gutter, Col, SpanLen, Sev),
        render_context_line(Line + 1, Lines, Gutter)
    ]),
    Context.

render_context_line(N, Lines, Gutter) when N >= 1, N =< length(Lines) ->
    LineStr = lists:nth(N, Lines),
    [dim([pad_num(N, Gutter), " | ", LineStr]), $\n];
render_context_line(_, _, _) ->
    [].

render_error_line(N, Lines, Gutter, _Sev) when N >= 1, N =< length(Lines) ->
    LineStr = lists:nth(N, Lines),
    [cyan(pad_num(N, Gutter)), dim(" | "), LineStr, $\n];
render_error_line(_, _, _, _) ->
    [].

render_caret_line(_N, _Lines, Gutter, Col, SpanLen, Sev) ->
    GutterPad = lists:duplicate(Gutter, $\s),
    %% Default: if no col info, underline from first non-whitespace
    {CaretCol, CaretLen} = case {Col, SpanLen} of
        {none, none}  -> {1, 1};
        {none, S}     -> {1, S};
        {C, none}     -> {C, 1};
        {C, S}        -> {C, max(1, S)}
    end,
    Padding = lists:duplicate(CaretCol - 1, $\s),
    Carets  = lists:duplicate(CaretLen, $^),
    ColorFn = case Sev of error -> fun red/1; warning -> fun yellow/1 end,
    [GutterPad, dim(" | "), Padding, ColorFn(bold(Carets)), $\n].

render_message(#diag{message = Msg, hint = none}) ->
    ["  ", binary_to_list(Msg), $\n];
render_message(#diag{message = Msg, hint = Hint}) ->
    ["  ", binary_to_list(Msg), $\n,
     "  ", dim(["Hint: ", binary_to_list(Hint)]), $\n].

%% ── Helpers ─────────────────────────────────────────────────────────────

source_lines(Source) when is_list(Source) ->
    string:split(Source, "\n", all);
source_lines(Source) when is_binary(Source) ->
    source_lines(binary_to_list(Source)).

get_source_line(Source, Line) ->
    Lines = source_lines(Source),
    case Line >= 1 andalso Line =< length(Lines) of
        true  -> lists:nth(Line, Lines);
        false -> ""
    end.

gutter_width(MaxLine) ->
    length(integer_to_list(max(1, MaxLine))).

pad_num(N, Width) ->
    S = integer_to_list(N),
    Pad = max(0, Width - length(S)),
    [lists:duplicate(Pad, $\s), S].

find_token_col(Token, Line) ->
    case string:find(Line, Token) of
        nomatch -> none;
        Found   -> length(Line) - length(Found) + 1
    end.

extract_parser_token(["syntax error before: ", TokenStr]) ->
    %% TokenStr is something like "'end'" or "'>='"
    strip_quotes(lists:flatten(TokenStr));
extract_parser_token(Msg) ->
    lists:flatten(io_lib:format("~s", [Msg])).

strip_quotes([$' | Rest]) ->
    case lists:reverse(Rest) of
        [$' | Inner] -> lists:reverse(Inner);
        _ -> Rest
    end;
strip_quotes(S) -> S.

quote(Token) ->
    ["'", Token, "'"].

suggest_parse_fix("end") ->
    <<"Did you close a block too early, or forget an expression?">>;
suggest_parse_fix(",") ->
    <<"Check for a trailing comma or missing argument.">>;
suggest_parse_fix("=") ->
    <<"The left side of '=' must be a variable or pattern.">>;
suggest_parse_fix(")") ->
    <<"Check for mismatched parentheses or a missing argument.">>;
suggest_parse_fix(_) ->
    none.

iol_size(IoList) ->
    byte_size(unicode:characters_to_binary(IoList)).

%% ── ANSI color helpers ──────────────────────────────────────────────────

color_enabled() ->
    case get(winn_color) of
        false -> false;
        _     -> true
    end.

ansi(Code, Text) ->
    case color_enabled() of
        true  -> [Code, Text, "\e[0m"];
        false -> Text
    end.

red(T)    -> ansi("\e[31m", T).
cyan(T)   -> ansi("\e[36m", T).
bold(T)   -> ansi("\e[1m", T).
dim(T)    -> ansi("\e[2m", T).
yellow(T) -> ansi("\e[33m", T).

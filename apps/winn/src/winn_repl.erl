%% winn_repl.erl
%% Interactive REPL for the Winn language.
%%
%% Each input line is wrapped in a temporary module, compiled in-memory,
%% executed, and the result is printed. Variable bindings persist across
%% evaluations by re-injecting them as Erlang term literals.

-module(winn_repl).
-export([start/0, get_binding/1, ensure_binding_table_test/0]).

-define(PROMPT, "winn> ").
-define(CONT_PROMPT, "  ... ").

start() ->
    io:format("Winn ~s (Erlang/OTP ~s)~n", [get_version(), erlang:system_info(otp_release)]),
    io:format("Type expressions to evaluate. Ctrl+C to exit.~n~n"),
    loop(#{bindings => #{}, counter => 0}).

loop(State) ->
    case read_input(?PROMPT) of
        eof ->
            io:format("~n"),
            ok;
        "" ->
            loop(State);
        Input ->
            case maybe_continue(Input) of
                {continue, Partial} ->
                    case read_continuation(Partial) of
                        eof ->
                            io:format("~n"),
                            ok;
                        FullInput ->
                            State2 = eval_and_print(FullInput, State),
                            loop(State2)
                    end;
                {complete, Line} ->
                    State2 = eval_and_print(Line, State),
                    loop(State2)
            end
    end.

%% ── Input reading ───────────────────────────────────────────────────────

read_input(Prompt) ->
    case io:get_line(Prompt) of
        eof -> eof;
        {error, _} -> eof;
        Data -> string:trim(Data, trailing, "\n")
    end.

read_continuation(Partial) ->
    case read_input(?CONT_PROMPT) of
        eof -> eof;
        Line ->
            Combined = Partial ++ "\n" ++ Line,
            case maybe_continue(Combined) of
                {continue, More} -> read_continuation(More);
                {complete, Full} -> Full
            end
    end.

maybe_continue(Input) ->
    Trimmed = string:trim(Input),
    case is_incomplete(Trimmed) of
        true  -> {continue, Trimmed};
        false -> {complete, Trimmed}
    end.

is_incomplete(Input) ->
    Opens  = count_char(Input, $() + count_char(Input, $[) + count_char(Input, ${),
    Closes = count_char(Input, $)) + count_char(Input, $]) + count_char(Input, $}),
    case Opens > Closes of
        true -> true;
        false ->
            Last = string:trim(Input, trailing),
            lists:any(fun(Suffix) -> lists:suffix(Suffix, Last) end,
                      ["|>", "=>", "->", "<>", "+", "-", "*", "/",
                       "=", "and", "or", "do", ","])
    end.

count_char([], _) -> 0;
count_char([C | Rest], C) -> 1 + count_char(Rest, C);
count_char([_ | Rest], C) -> count_char(Rest, C).

%% ── Eval and print ──────────────────────────────────────────────────────

eval_and_print(Input, #{counter := N, bindings := Bindings} = State) ->
    ModName = "WinnRepl" ++ integer_to_list(N),
    ModAtom = list_to_atom(string:lowercase(ModName)),

    %% Detect if this is an assignment: name = expr
    {IsAssign, VarName} = detect_assignment(Input),

    %% Build source with bindings injected
    Source = build_source(ModName, Input, Bindings),

    case compile_eval(Source, ModAtom) of
        {ok, Result} ->
            print_result(Result),
            NewBindings = case IsAssign of
                true  -> Bindings#{VarName => Result};
                false -> Bindings
            end,
            State#{counter := N + 1, bindings := NewBindings};
        {error, Reason} ->
            print_error(Reason),
            State#{counter := N + 1}
    end.

%% Detect "name = expr" assignments.
detect_assignment(Input) ->
    case re:run(Input, "^\\s*([a-z_][a-zA-Z0-9_]*)\\s*=\\s*", [{capture, [1], list}]) of
        {match, [VarName]} -> {true, VarName};
        nomatch            -> {false, none}
    end.

%% Build a Winn source string wrapping the input in a module.
%% Bindings are stored in ETS and retrieved via Erlang.winn_repl:get_binding/1.
build_source(ModName, Input, Bindings) ->
    %% Store bindings in ETS so the compiled code can retrieve them
    ensure_binding_table(),
    maps:foreach(fun(Name, Value) ->
        ets:insert(winn_repl_bindings, {Name, Value})
    end, Bindings),
    %% Inject binding retrieval lines
    BindingLines = maps:fold(fun(Name, _Value, Acc) ->
        Line = io_lib:format("    ~s = ReplBindings.get(\"~s\")\n", [Name, Name]),
        [Line | Acc]
    end, [], Bindings),
    lists:flatten([
        "module ", ModName, "\n",
        "  def __eval__()\n",
        BindingLines,
        "    ", Input, "\n",
        "  end\n",
        "end\n"
    ]).

compile_eval(Source, ModAtom) ->
    try
        {ok, Tokens, _} = winn_lexer:string(Source),
        {ok, AST}       = winn_parser:parse(Tokens),
        Transformed     = winn_transform:transform(AST),
        [CoreMod]       = winn_codegen:gen(Transformed),
        {ok, _CompiledMod, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
        code:purge(ModAtom),
        {module, ModAtom} = code:load_binary(ModAtom, "repl", Bin),
        Result = ModAtom:'__eval__'(),
        code:purge(ModAtom),
        code:delete(ModAtom),
        {ok, Result}
    catch
        error:{badmatch, {error, {Line, winn_lexer, Err}}} ->
            {error, fmt("Syntax error (line ~p): ~s", [Line, winn_lexer:format_error(Err)])};
        error:{badmatch, {error, {Line, winn_parser, Msg}}} ->
            {error, fmt("Parse error: ~s", [lists:flatten(Msg)])};
        error:{badmatch, {error, Errors}} when is_list(Errors) ->
            {error, fmt("Compile error: ~p", [Errors])};
        error:{badmatch, {error, Reason}} ->
            {error, fmt("Error: ~p", [Reason])};
        error:undef:Stack ->
            case Stack of
                [{_M, F, _A, _} | _] ->
                    {error, fmt("Undefined function: ~s", [F])};
                _ ->
                    {error, fmt("Undefined function")}
            end;
        error:{badkey, Key} ->
            {error, fmt("Key not found: ~p", [Key])};
        error:badarith ->
            {error, fmt("Arithmetic error (division by zero?)")};
        error:Reason:Stack ->
            case Stack of
                [{_, '__eval__', _, _} | _] ->
                    {error, fmt("~p", [Reason])};
                [Top | _] ->
                    {error, fmt("~p in ~p", [Reason, Top])};
                _ ->
                    {error, fmt("~p", [Reason])}
            end;
        throw:Val ->
            {error, fmt("Uncaught throw: ~p", [Val])};
        exit:Reason ->
            {error, fmt("Exit: ~p", [Reason])}
    end.

%% ── Output ──────────────────────────────────────────────────────────────

print_result(ok) -> ok;  %% Suppress bare :ok from IO.puts etc.
print_result(nil) -> io:format("nil~n");
print_result(Result) when is_binary(Result) ->
    io:format("\"~s\"~n", [Result]);
print_result(Result) when is_atom(Result) ->
    io:format(":~s~n", [Result]);
print_result(Result) ->
    io:format("~p~n", [Result]).

print_error(Reason) ->
    io:format("\e[31merror:\e[0m ~s~n", [lists:flatten(Reason)]).

fmt(Format, Args) ->
    lists:flatten(io_lib:format(Format, Args)).
fmt(Msg) -> Msg.

%% ── Binding storage (ETS) ────────────────────────────────────────────────

ensure_binding_table() ->
    case ets:whereis(winn_repl_bindings) of
        undefined ->
            ets:new(winn_repl_bindings, [named_table, public, set]),
            ok;
        _ ->
            ok
    end.

%% Exported for tests.
ensure_binding_table_test() -> ensure_binding_table().

%% Called by compiled REPL modules to retrieve a stored binding.
get_binding(Name) when is_binary(Name) ->
    get_binding(binary_to_list(Name));
get_binding(Name) when is_list(Name) ->
    case ets:lookup(winn_repl_bindings, Name) of
        [{_, Value}] -> Value;
        []           -> nil
    end.

get_version() ->
    case application:get_key(winn, vsn) of
        {ok, Vsn} -> Vsn;
        _         -> "0.2.0"
    end.

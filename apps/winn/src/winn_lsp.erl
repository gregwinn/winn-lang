%% winn_lsp.erl
%% Language Server Protocol implementation for Winn.
%%
%% Supports:
%%   - textDocument/publishDiagnostics (inline compile errors)
%%   - textDocument/completion (module function autocomplete)
%%   - textDocument/didOpen, didChange, didSave
%%
%% Transport: stdio with Content-Length framed JSON-RPC 2.0.

-module(winn_lsp).
-export([start/0, compile_for_diagnostics/1, document_symbols/1, hover_at/3]).

%% ── Entry point ───────────────────────────────────────────────────────────

start() ->
    %% Disable error logger output so it doesn't corrupt the LSP stream
    logger:set_primary_config(level, none),
    loop(#{}).

%% ── Main loop ─────────────────────────────────────────────────────────────

loop(State) ->
    case read_message() of
        {ok, Msg} ->
            State2 = handle_message(Msg, State),
            loop(State2);
        eof ->
            ok;
        {error, _} ->
            ok
    end.

%% ── Message handling ──────────────────────────────────────────────────────

handle_message(#{<<"method">> := <<"initialize">>, <<"id">> := Id} = _Msg, State) ->
    Result = #{
        <<"capabilities">> => #{
            <<"textDocumentSync">> => #{
                <<"openClose">> => true,
                <<"change">> => 1,  %% Full document sync
                <<"save">> => #{<<"includeText">> => true}
            },
            <<"completionProvider">> => #{
                <<"triggerCharacters">> => [<<".">>]
            },
            <<"documentSymbolProvider">> => true,
            <<"hoverProvider">> => true
        },
        <<"serverInfo">> => #{
            <<"name">> => <<"winn-lsp">>,
            <<"version">> => <<"0.9.0">>
        }
    },
    send_response(Id, Result),
    State;

handle_message(#{<<"method">> := <<"initialized">>}, State) ->
    State;

handle_message(#{<<"method">> := <<"shutdown">>, <<"id">> := Id}, State) ->
    send_response(Id, null),
    State#{shutdown => true};

handle_message(#{<<"method">> := <<"exit">>}, _State) ->
    halt(0),
    #{};

handle_message(#{<<"method">> := <<"textDocument/didOpen">>, <<"params">> := Params}, State) ->
    #{<<"textDocument">> := #{<<"uri">> := Uri, <<"text">> := Text}} = Params,
    publish_diagnostics(Uri, Text),
    maps:put(Uri, Text, State);

handle_message(#{<<"method">> := <<"textDocument/didChange">>, <<"params">> := Params}, State) ->
    #{<<"textDocument">> := #{<<"uri">> := Uri},
      <<"contentChanges">> := [#{<<"text">> := Text} | _]} = Params,
    publish_diagnostics(Uri, Text),
    maps:put(Uri, Text, State);

handle_message(#{<<"method">> := <<"textDocument/didSave">>, <<"params">> := Params}, State) ->
    #{<<"textDocument">> := #{<<"uri">> := Uri}} = Params,
    Text = case Params of
        #{<<"text">> := T} -> T;
        _ -> maps:get(Uri, State, <<>>)
    end,
    publish_diagnostics(Uri, Text),
    maps:put(Uri, Text, State);

handle_message(#{<<"method">> := <<"textDocument/didClose">>, <<"params">> := Params}, State) ->
    #{<<"textDocument">> := #{<<"uri">> := Uri}} = Params,
    publish_empty_diagnostics(Uri),
    maps:remove(Uri, State);

handle_message(#{<<"method">> := <<"textDocument/documentSymbol">>, <<"id">> := Id,
                 <<"params">> := Params}, State) ->
    #{<<"textDocument">> := #{<<"uri">> := Uri}} = Params,
    Text = maps:get(Uri, State, <<>>),
    Symbols = document_symbols(binary_to_list(Text)),
    send_response(Id, Symbols),
    State;

handle_message(#{<<"method">> := <<"textDocument/hover">>, <<"id">> := Id,
                 <<"params">> := Params}, State) ->
    #{<<"textDocument">> := #{<<"uri">> := Uri},
      <<"position">> := #{<<"line">> := Line, <<"character">> := Char}} = Params,
    Text = maps:get(Uri, State, <<>>),
    Result = hover_at(binary_to_list(Text), Line, Char),
    send_response(Id, Result),
    State;

handle_message(#{<<"method">> := <<"textDocument/completion">>, <<"id">> := Id,
                 <<"params">> := Params}, State) ->
    #{<<"textDocument">> := #{<<"uri">> := Uri},
      <<"position">> := #{<<"line">> := Line, <<"character">> := Char}} = Params,
    Text = maps:get(Uri, State, <<>>),
    Items = compute_completions(Text, Line, Char),
    send_response(Id, Items),
    State;

%% Ignore unknown methods
handle_message(#{<<"id">> := Id}, State) ->
    send_response(Id, null),
    State;
handle_message(_, State) ->
    State.

%% ── Diagnostics ───────────────────────────────────────────────────────────

publish_diagnostics(Uri, Text) ->
    Source = binary_to_list(Text),
    publish(Uri, compile_for_diagnostics(Source)).

publish_empty_diagnostics(Uri) ->
    publish(Uri, []).

publish(Uri, Diagnostics) ->
    Notification = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"textDocument/publishDiagnostics">>,
        <<"params">> => #{
            <<"uri">> => Uri,
            <<"diagnostics">> => Diagnostics
        }
    },
    send_notification(Notification).

compile_for_diagnostics(Source) ->
    try
        case winn_lexer:string(Source) of
            {ok, RawTokens, _} ->
                Tokens = winn_newline_filter:filter(RawTokens),
                case winn_parser:parse(Tokens) of
                    {ok, Forms} ->
                        SemDiags = case winn_semantic:analyse(Forms) of
                            {ok, Analysed} ->
                                try
                                    _Transformed = winn_transform:transform(Analysed),
                                    []
                                catch
                                    _:Reason ->
                                        Line = extract_line(Reason),
                                        [make_diagnostic(Line, format_error(Reason), 1)]
                                end;
                            {error, Errors} ->
                                [make_diagnostic(L, unicode:characters_to_binary(M), severity(S))
                                 || {S, L, _Name, M} <- Errors]
                        end,
                        SemDiags ++ lint_diagnostics(Source);
                    {error, {Line, winn_parser, Msg}} ->
                        [make_diagnostic(Line, format_parse_error(Msg), 1)]
                end;
            {error, {Line, winn_lexer, Error}, _} ->
                ErrMsg = unicode:characters_to_binary(
                    ["Unexpected character: ", winn_lexer:format_error(Error)]),
                [make_diagnostic(Line, ErrMsg, 1)]
        end
    catch
        _:_ -> []
    end.

%% Run the linter and convert each warning to an LSP diagnostic.
%% Only invoked when parsing succeeded, so lint will parse cleanly too.
lint_diagnostics(Source) ->
    try winn_lint:check_string(Source) of
        {ok, Violations} ->
            [make_lint_diagnostic(V) || V <- Violations];
        {error, _} ->
            []
    catch
        _:_ -> []
    end.

make_lint_diagnostic({Sev, Line, Rule, Msg}) ->
    Base = make_diagnostic(Line, ensure_binary(Msg), severity(Sev)),
    Base#{<<"code">> => atom_to_binary(Rule, utf8)}.

make_diagnostic(Line, Message, Severity) ->
    L = case Line of
        none -> 0;
        N when is_integer(N) -> max(0, N - 1)  %% LSP is 0-indexed
    end,
    #{
        <<"range">> => #{
            <<"start">> => #{<<"line">> => L, <<"character">> => 0},
            <<"end">> => #{<<"line">> => L, <<"character">> => 999}
        },
        <<"severity">> => Severity,
        <<"source">> => <<"winn">>,
        <<"message">> => ensure_binary(Message)
    }.

severity(error) -> 1;
severity(warning) -> 2;
severity(_) -> 1.

format_parse_error(["syntax error before: ", TokenStr]) ->
    unicode:characters_to_binary(["Syntax error: unexpected ", lists:flatten(TokenStr)]);
format_parse_error(Msg) ->
    unicode:characters_to_binary(io_lib:format("~s", [Msg])).

format_error({unsupported_pipe_block_target, _}) ->
    <<"The right side of |> must be a function call.">>;
format_error({unsupported_block_call_target, _}) ->
    <<"A do...end block must follow a function call.">>;
format_error(Reason) ->
    unicode:characters_to_binary(io_lib:format("~p", [Reason])).

extract_line(Term) when is_tuple(Term), tuple_size(Term) >= 2 ->
    case element(2, Term) of
        L when is_integer(L) -> L;
        _ -> none
    end;
extract_line(_) -> none.

%% ── Document symbols ──────────────────────────────────────────────────────

%% Parse source and return an LSP DocumentSymbol[] tree.
%% Top level entries are modules/agents; their children are functions,
%% imports, and aliases. Returns [] on parse failure (the editor falls
%% back to its diagnostic squiggles).
document_symbols(Source) ->
    try
        case winn_lexer:string(Source) of
            {ok, RawTokens, _} ->
                Tokens = winn_newline_filter:filter(RawTokens),
                case winn_parser:parse(Tokens) of
                    {ok, Forms} -> [form_symbol(F) || F <- Forms, is_top_form(F)];
                    _ -> []
                end;
            _ -> []
        end
    catch
        _:_ -> []
    end.

is_top_form({module, _, _, _}) -> true;
is_top_form({agent, _, _, _})  -> true;
is_top_form(_) -> false.

form_symbol({module, Line, Name, Body}) ->
    container_symbol(Name, Line, 2, body_children(Body));   %% Module = 2
form_symbol({agent, Line, Name, Body}) ->
    container_symbol(Name, Line, 5, body_children(Body)).   %% Class  = 5

body_children(Body) ->
    lists:flatmap(fun child_symbol/1, Body).

child_symbol({function, Line, Name, Params, _Body}) ->
    [function_symbol(Name, length(Params), Line)];
child_symbol({function_g, Line, Name, Params, _Guard, _Body}) ->
    [function_symbol(Name, length(Params), Line)];
child_symbol({agent_fn, Line, Name, Params, _Body}) ->
    [function_symbol(Name, length(Params), Line)];
child_symbol({agent_fn_g, Line, Name, Params, _Guard, _Body}) ->
    [function_symbol(Name, length(Params), Line)];
child_symbol({agent_cast_fn, Line, Name, Params, _Body}) ->
    [function_symbol(Name, length(Params), Line)];
child_symbol({import_directive, Line, ModName}) ->
    [leaf_symbol(atom_to_binary(ModName, utf8), Line, 3)];   %% Namespace = 3
child_symbol({alias_directive, Line, Parent, Short}) ->
    Label = <<(atom_to_binary(Parent, utf8))/binary, ".",
              (atom_to_binary(Short, utf8))/binary>>,
    [leaf_symbol(Label, Line, 3)];
child_symbol(_) ->
    [].

function_symbol(Name, Arity, Line) ->
    Label = unicode:characters_to_binary(
        io_lib:format("~s/~B", [atom_to_list(Name), Arity])),
    leaf_symbol(Label, Line, 12).                            %% Function = 12

container_symbol(Name, Line, Kind, Children) ->
    Range = line_range(Line),
    #{
        <<"name">>           => atom_to_binary(Name, utf8),
        <<"kind">>           => Kind,
        <<"range">>          => Range,
        <<"selectionRange">> => Range,
        <<"children">>       => Children
    }.

leaf_symbol(Name, Line, Kind) ->
    Range = line_range(Line),
    #{
        <<"name">>           => Name,
        <<"kind">>           => Kind,
        <<"range">>          => Range,
        <<"selectionRange">> => Range,
        <<"children">>       => []
    }.

line_range(Line) ->
    L = max(0, Line - 1),
    #{
        <<"start">> => #{<<"line">> => L, <<"character">> => 0},
        <<"end">>   => #{<<"line">> => L, <<"character">> => 0}
    }.

%% ── Hover ─────────────────────────────────────────────────────────────────

%% Look up the identifier at the given LSP position and return an LSP
%% Hover response, or `null` if nothing useful sits at the cursor.
%% Line and Char are 0-indexed (LSP convention).
hover_at(Source, Line, Char) ->
    case identifier_at(Source, Line, Char) of
        none -> null;
        {ok, Name} ->
            case lookup_function(Source, Name) of
                {ok, {DefLine, Params}} ->
                    Doc = doc_comment_for(Source, DefLine),
                    build_hover(Name, Params, Doc);
                none -> null
            end
    end.

identifier_at(Source, Line, Char) ->
    Lines = split_lines(Source),
    case nth_or_none(Line + 1, Lines) of
        none -> none;
        LineStr -> word_at(LineStr, Char)
    end.

split_lines(Source) -> split_lines(Source, [], []).
split_lines([], Cur, Acc) -> lists:reverse([lists:reverse(Cur) | Acc]);
split_lines([$\n | Rest], Cur, Acc) -> split_lines(Rest, [], [lists:reverse(Cur) | Acc]);
split_lines([C | Rest], Cur, Acc) -> split_lines(Rest, [C | Cur], Acc).

nth_or_none(N, _) when N =< 0 -> none;
nth_or_none(N, L) when N > length(L) -> none;
nth_or_none(N, L) -> lists:nth(N, L).

%% Extract the identifier surrounding column Col (0-indexed) on a line.
%% Identifier chars: a-zA-Z0-9_? — Winn allows trailing `?`.
word_at(_, Col) when Col < 0 -> none;
word_at(LineStr, Col) ->
    Len = length(LineStr),
    case Col >= Len of
        true -> none;
        false ->
            case ident_char(lists:nth(Col + 1, LineStr)) of
                false -> none;
                true ->
                    Start = expand_left(LineStr, Col),
                    End   = expand_right(LineStr, Col, Len),
                    {ok, lists:sublist(LineStr, Start + 1, End - Start)}
            end
    end.

%% Walk left while the char immediately to the left is an ident char.
%% Returns the 0-indexed start of the word (inclusive).
expand_left(_, 0) -> 0;
expand_left(LineStr, Col) ->
    case ident_char(lists:nth(Col, LineStr)) of
        true  -> expand_left(LineStr, Col - 1);
        false -> Col
    end.

%% Walk right while the char immediately to the right is an ident char.
%% Returns the 0-indexed end of the word (exclusive).
expand_right(_, Col, Len) when Col + 1 >= Len -> Len;
expand_right(LineStr, Col, Len) ->
    case ident_char(lists:nth(Col + 2, LineStr)) of
        true  -> expand_right(LineStr, Col + 1, Len);
        false -> Col + 1
    end.

ident_char(C) when C >= $a, C =< $z -> true;
ident_char(C) when C >= $A, C =< $Z -> true;
ident_char(C) when C >= $0, C =< $9 -> true;
ident_char($_) -> true;
ident_char($?) -> true;
ident_char(_)  -> false.

%% Find the first function (or agent fn) named Name in the source.
lookup_function(Source, Name) ->
    try
        {ok, RawTokens, _} = winn_lexer:string(Source),
        Tokens = winn_newline_filter:filter(RawTokens),
        {ok, Forms} = winn_parser:parse(Tokens),
        Target = list_to_atom(Name),
        find_fn(Forms, Target)
    catch
        _:_ -> none
    end.

find_fn([], _) -> none;
find_fn([{module, _, _, Body} | Rest], Name) ->
    case find_fn_in_body(Body, Name) of
        none -> find_fn(Rest, Name);
        Found -> Found
    end;
find_fn([{agent, _, _, Body} | Rest], Name) ->
    case find_fn_in_body(Body, Name) of
        none -> find_fn(Rest, Name);
        Found -> Found
    end;
find_fn([_ | Rest], Name) -> find_fn(Rest, Name).

find_fn_in_body([], _) -> none;
find_fn_in_body([{function, Line, Name, Params, _} | _], Name) ->
    {ok, {Line, Params}};
find_fn_in_body([{function_g, Line, Name, Params, _, _} | _], Name) ->
    {ok, {Line, Params}};
find_fn_in_body([{agent_fn, Line, Name, Params, _} | _], Name) ->
    {ok, {Line, Params}};
find_fn_in_body([{agent_fn_g, Line, Name, Params, _, _} | _], Name) ->
    {ok, {Line, Params}};
find_fn_in_body([{agent_cast_fn, Line, Name, Params, _} | _], Name) ->
    {ok, {Line, Params}};
find_fn_in_body([_ | Rest], Name) ->
    find_fn_in_body(Rest, Name).

%% Collect consecutive `# ...` line comments immediately preceding DefLine.
doc_comment_for(Source, DefLine) ->
    Comments = winn_comment:extract(Source),
    Lines = [{L, strip_hash(T)} || {L, T, line} <- Comments],
    LineMap = maps:from_list(Lines),
    walk_back(DefLine - 1, LineMap, []).

walk_back(Line, _Map, Acc) when Line < 1 -> finish_doc(Acc);
walk_back(Line, Map, Acc) ->
    case maps:find(Line, Map) of
        {ok, Text} -> walk_back(Line - 1, Map, [Text | Acc]);
        error      -> finish_doc(Acc)
    end.

finish_doc([]) -> none;
finish_doc(Lines) ->
    unicode:characters_to_binary(string:join(Lines, "\n")).

strip_hash([$#, $\s | Rest]) -> Rest;
strip_hash([$# | Rest]) -> Rest;
strip_hash(Other) -> Other.

build_hover(Name, Params, Doc) ->
    ParamStrs = [param_name(P) || P <- Params],
    Sig = io_lib:format("**~s/~B** — `def ~s(~s)`",
                        [Name, length(Params), Name, string:join(ParamStrs, ", ")]),
    Body = case Doc of
        none -> Sig;
        _    -> [Sig, "\n\n", Doc]
    end,
    Value = unicode:characters_to_binary(Body),
    #{
        <<"contents">> => #{
            <<"kind">>  => <<"markdown">>,
            <<"value">> => Value
        }
    }.

param_name({var, _, Name})        -> atom_to_list(Name);
param_name({pat_var, _, Name})    -> atom_to_list(Name);
param_name({pat_wildcard, _})     -> "_";
param_name({pat_atom, _, A})      -> atom_to_list(A);
param_name(_)                     -> "_".

%% ── Completions ───────────────────────────────────────────────────────────

compute_completions(Text, Line, Char) ->
    %% Get the line text and find the module name before the dot
    Lines = binary:split(Text, <<"\n">>, [global]),
    case Line < length(Lines) of
        true ->
            LineText = lists:nth(Line + 1, Lines),
            Prefix = binary:part(LineText, 0, min(Char, byte_size(LineText))),
            case extract_module_prefix(Prefix) of
                {ok, ModName} -> module_completions(ModName);
                none -> []
            end;
        false ->
            []
    end.

extract_module_prefix(Prefix) ->
    %% Find the last Module. pattern
    case re:run(Prefix, "([A-Z][a-zA-Z0-9]*)\\.$", [{capture, [1], binary}]) of
        {match, [ModName]} -> {ok, ModName};
        nomatch -> none
    end.

module_completions(<<"IO">>) ->
    [completion(<<"puts">>, <<"IO.puts(value)">>, <<"Print to stdout">>),
     completion(<<"print">>, <<"IO.print(value)">>, <<"Print without newline">>),
     completion(<<"inspect">>, <<"IO.inspect(value)">>, <<"Debug print and return">>)];
module_completions(<<"String">>) ->
    [completion(<<"upcase">>, <<"String.upcase(str)">>, <<"Convert to uppercase">>),
     completion(<<"downcase">>, <<"String.downcase(str)">>, <<"Convert to lowercase">>),
     completion(<<"trim">>, <<"String.trim(str)">>, <<"Remove whitespace">>),
     completion(<<"length">>, <<"String.length(str)">>, <<"String length">>),
     completion(<<"split">>, <<"String.split(str, sep)">>, <<"Split string">>),
     completion(<<"contains?">>, <<"String.contains?(str, sub)">>, <<"Check substring">>),
     completion(<<"replace">>, <<"String.replace(str, old, new)">>, <<"Replace substring">>),
     completion(<<"starts_with?">>, <<"String.starts_with?(str, prefix)">>, <<"Check prefix">>),
     completion(<<"ends_with?">>, <<"String.ends_with?(str, suffix)">>, <<"Check suffix">>),
     completion(<<"slice">>, <<"String.slice(str, start, len)">>, <<"Substring">>),
     completion(<<"pad_left">>, <<"String.pad_left(str, len, char)">>, <<"Left pad">>),
     completion(<<"pad_right">>, <<"String.pad_right(str, len, char)">>, <<"Right pad">>),
     completion(<<"repeat">>, <<"String.repeat(str, n)">>, <<"Repeat string">>)];
module_completions(<<"Enum">>) ->
    [completion(<<"map">>, <<"Enum.map(list) do |x| ... end">>, <<"Transform elements">>),
     completion(<<"filter">>, <<"Enum.filter(list) do |x| ... end">>, <<"Filter elements">>),
     completion(<<"reduce">>, <<"Enum.reduce(list, acc) do |x, acc| ... end">>, <<"Reduce to value">>),
     completion(<<"each">>, <<"Enum.each(list) do |x| ... end">>, <<"Iterate elements">>),
     completion(<<"find">>, <<"Enum.find(list) do |x| ... end">>, <<"Find first match">>),
     completion(<<"any?">>, <<"Enum.any?(list) do |x| ... end">>, <<"Check if any match">>),
     completion(<<"all?">>, <<"Enum.all?(list) do |x| ... end">>, <<"Check if all match">>),
     completion(<<"count">>, <<"Enum.count(list)">>, <<"Count elements">>),
     completion(<<"sort">>, <<"Enum.sort(list)">>, <<"Sort elements">>),
     completion(<<"reverse">>, <<"Enum.reverse(list)">>, <<"Reverse list">>),
     completion(<<"join">>, <<"Enum.join(list, sep)">>, <<"Join as string">>),
     completion(<<"flat_map">>, <<"Enum.flat_map(list) do |x| ... end">>, <<"Map and flatten">>)];
module_completions(<<"List">>) ->
    [completion(<<"first">>, <<"List.first(list)">>, <<"First element">>),
     completion(<<"last">>, <<"List.last(list)">>, <<"Last element">>),
     completion(<<"length">>, <<"List.length(list)">>, <<"List length">>),
     completion(<<"append">>, <<"List.append(list, item)">>, <<"Append element">>),
     completion(<<"flatten">>, <<"List.flatten(list)">>, <<"Flatten nested">>),
     completion(<<"contains?">>, <<"List.contains?(list, item)">>, <<"Check membership">>)];
module_completions(<<"Map">>) ->
    [completion(<<"get">>, <<"Map.get(key, map)">>, <<"Get value by key">>),
     completion(<<"put">>, <<"Map.put(key, value, map)">>, <<"Set key-value">>),
     completion(<<"merge">>, <<"Map.merge(map1, map2)">>, <<"Merge maps">>),
     completion(<<"keys">>, <<"Map.keys(map)">>, <<"List keys">>),
     completion(<<"values">>, <<"Map.values(map)">>, <<"List values">>),
     completion(<<"has_key?">>, <<"Map.has_key?(map, key)">>, <<"Check key exists">>),
     completion(<<"delete">>, <<"Map.delete(map, key)">>, <<"Remove key">>)];
module_completions(<<"Server">>) ->
    [completion(<<"start">>, <<"Server.start(Router, port)">>, <<"Start HTTP server">>),
     completion(<<"json">>, <<"Server.json(conn, data)">>, <<"JSON response">>),
     completion(<<"text">>, <<"Server.text(conn, str)">>, <<"Text response">>),
     completion(<<"path_param">>, <<"Server.path_param(conn, name)">>, <<"Get path parameter">>),
     completion(<<"body_params">>, <<"Server.body_params(conn)">>, <<"Get body params">>)];
module_completions(<<"HTTP">>) ->
    [completion(<<"get">>, <<"HTTP.get(url)">>, <<"GET request">>),
     completion(<<"post">>, <<"HTTP.post(url, body)">>, <<"POST request">>),
     completion(<<"put">>, <<"HTTP.put(url, body)">>, <<"PUT request">>),
     completion(<<"delete">>, <<"HTTP.delete(url)">>, <<"DELETE request">>)];
module_completions(<<"JSON">>) ->
    [completion(<<"encode">>, <<"JSON.encode(data)">>, <<"Encode to JSON">>),
     completion(<<"decode">>, <<"JSON.decode(str)">>, <<"Decode from JSON">>)];
module_completions(<<"Logger">>) ->
    [completion(<<"info">>, <<"Logger.info(msg)">>, <<"Info log">>),
     completion(<<"debug">>, <<"Logger.debug(msg)">>, <<"Debug log">>),
     completion(<<"warn">>, <<"Logger.warn(msg)">>, <<"Warning log">>),
     completion(<<"error">>, <<"Logger.error(msg)">>, <<"Error log">>)];
module_completions(<<"File">>) ->
    [completion(<<"read">>, <<"File.read(path)">>, <<"Read file contents">>),
     completion(<<"write">>, <<"File.write(path, data)">>, <<"Write to file">>),
     completion(<<"exists?">>, <<"File.exists?(path)">>, <<"Check if file exists">>),
     completion(<<"delete">>, <<"File.delete(path)">>, <<"Delete file">>),
     completion(<<"list">>, <<"File.list(dir)">>, <<"List directory">>),
     completion(<<"mkdir">>, <<"File.mkdir(path)">>, <<"Create directory">>)];
module_completions(<<"Repo">>) ->
    [completion(<<"all">>, <<"Repo.all(Model)">>, <<"Fetch all records">>),
     completion(<<"get">>, <<"Repo.get(Model, id)">>, <<"Fetch by ID">>),
     completion(<<"insert">>, <<"Repo.insert(Model, attrs)">>, <<"Insert record">>),
     completion(<<"delete">>, <<"Repo.delete(record)">>, <<"Delete record">>),
     completion(<<"transaction">>, <<"Repo.transaction(fn() => ... end)">>, <<"Database transaction">>)];
module_completions(<<"System">>) ->
    [completion(<<"get_env">>, <<"System.get_env(key, default)">>, <<"Get env variable">>),
     completion(<<"put_env">>, <<"System.put_env(key, value)">>, <<"Set env variable">>)];
module_completions(<<"Task">>) ->
    [completion(<<"async">>, <<"Task.async(fn() => ... end)">>, <<"Async task">>),
     completion(<<"await">>, <<"Task.await(task)">>, <<"Await result">>),
     completion(<<"async_all">>, <<"Task.async_all(list) do |x| ... end">>, <<"Parallel map">>)];
module_completions(<<"Regex">>) ->
    [completion(<<"match?">>, <<"Regex.match?(pattern, str)">>, <<"Test regex match">>),
     completion(<<"replace">>, <<"Regex.replace(pattern, str, replacement)">>, <<"Regex replace">>),
     completion(<<"scan">>, <<"Regex.scan(pattern, str)">>, <<"Find all matches">>),
     completion(<<"split">>, <<"Regex.split(pattern, str)">>, <<"Split by regex">>)];
module_completions(<<"Agent">>) ->
    [completion(<<"stop">>, <<"Agent.stop(pid)">>, <<"Stop an agent">>)];
module_completions(_) ->
    [].

completion(Label, Detail, Doc) ->
    #{
        <<"label">> => Label,
        <<"kind">> => 3,  %% Function
        <<"detail">> => Detail,
        <<"documentation">> => Doc
    }.

%% ── JSON-RPC transport (stdio) ────────────────────────────────────────────

read_message() ->
    case read_headers() of
        {ok, ContentLength} ->
            case io:get_chars("", ContentLength) of
                eof -> eof;
                {error, _} = Err -> Err;
                Data ->
                    Bin = iolist_to_binary(Data),
                    {ok, jsone:decode(Bin)}
            end;
        Other -> Other
    end.

read_headers() ->
    read_headers(none).

read_headers(ContentLength) ->
    case io:get_line("") of
        eof -> eof;
        {error, _} = Err -> Err;
        Line ->
            Trimmed = string:trim(Line),
            case Trimmed of
                "" ->
                    %% Empty line = end of headers
                    case ContentLength of
                        none -> {error, no_content_length};
                        N -> {ok, N}
                    end;
                _ ->
                    case parse_header(Trimmed) of
                        {content_length, N} -> read_headers(N);
                        _ -> read_headers(ContentLength)
                    end
            end
    end.

parse_header(Line) ->
    case string:split(Line, ":") of
        [Key, Value] ->
            case string:lowercase(string:trim(Key)) of
                "content-length" ->
                    {content_length, list_to_integer(string:trim(Value))};
                _ ->
                    unknown
            end;
        _ ->
            unknown
    end.

send_response(Id, Result) ->
    Msg = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"id">> => Id,
        <<"result">> => Result
    },
    send_json(Msg).

send_notification(Msg) ->
    send_json(Msg).

send_json(Msg) ->
    Body = jsone:encode(Msg),
    Header = io_lib:format("Content-Length: ~B\r\n\r\n", [byte_size(Body)]),
    io:format("~s~s", [Header, Body]).

ensure_binary(B) when is_binary(B) -> B;
ensure_binary(L) when is_list(L) -> unicode:characters_to_binary(L);
ensure_binary(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other])).

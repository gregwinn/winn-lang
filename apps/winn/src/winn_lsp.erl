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
-export([start/0, compile_for_diagnostics/1]).

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
            }
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

handle_message(#{<<"method">> := <<"textDocument/didClose">>}, State) ->
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
    Diagnostics = compile_for_diagnostics(Source),
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
                        case winn_semantic:analyse(Forms) of
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
                        end;
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

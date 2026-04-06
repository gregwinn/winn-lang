%% winn_comment.erl
%% Extract comments from Winn source code with line numbers.
%% Scans raw source text (not tokens) so comments are preserved
%% even though the lexer discards them.

-module(winn_comment).
-export([extract/1]).

%% extract(Source) -> [{Line, Text, Type}]
%%   Line = integer() — 1-based line number
%%   Text = string()  — the comment text including # prefix
%%   Type = line | block
extract(Source) when is_list(Source) ->
    scan(Source, 1, normal, [], []).

%% State machine: normal | in_string | in_triple_string | in_block_comment
%% Args: Chars, Line, State, CurrentComment, Acc

%% End of input
scan([], _Line, _State, [], Acc) ->
    lists:reverse(Acc);
scan([], Line, in_block_comment, Cur, Acc) ->
    Text = lists:reverse(Cur),
    lists:reverse([{Line, Text, block} | Acc]);
scan([], _Line, _State, _Cur, Acc) ->
    lists:reverse(Acc);

%% === Normal state ===

%% Triple-quoted string start
scan([$", $", $" | Rest], Line, normal, Cur, Acc) ->
    scan(Rest, Line, in_triple_string, Cur, Acc);
%% Regular string start
scan([$" | Rest], Line, normal, Cur, Acc) ->
    scan(Rest, Line, in_string, Cur, Acc);
%% Block comment start: #|
scan([$#, $| | Rest], Line, normal, _Cur, Acc) ->
    scan(Rest, Line, in_block_comment, [$|, $#], Acc);
%% Line comment: # (not followed by |)
scan([$# | Rest], Line, normal, _Cur, Acc) ->
    {CommentText, Remaining} = collect_line_comment([$# | Rest]),
    scan(Remaining, Line, normal, [], [{Line, CommentText, line} | Acc]);
%% Newline in normal
scan([$\n | Rest], Line, normal, Cur, Acc) ->
    scan(Rest, Line + 1, normal, Cur, Acc);
%% Any other char in normal
scan([_ | Rest], Line, normal, Cur, Acc) ->
    scan(Rest, Line, normal, Cur, Acc);

%% === In regular string ===

%% Escaped char in string — skip both
scan([$\\, _ | Rest], Line, in_string, Cur, Acc) ->
    scan(Rest, Line, in_string, Cur, Acc);
%% String interpolation start #{
scan([$#, ${ | Rest], Line, in_string, Cur, Acc) ->
    {Remaining, NewLine} = skip_interp(Rest, Line, 0),
    scan(Remaining, NewLine, in_string, Cur, Acc);
%% End of string
scan([$" | Rest], Line, in_string, Cur, Acc) ->
    scan(Rest, Line, normal, Cur, Acc);
%% Newline in string
scan([$\n | Rest], Line, in_string, Cur, Acc) ->
    scan(Rest, Line + 1, in_string, Cur, Acc);
%% Any char in string
scan([_ | Rest], Line, in_string, Cur, Acc) ->
    scan(Rest, Line, in_string, Cur, Acc);

%% === In triple-quoted string ===

%% End of triple string
scan([$", $", $" | Rest], Line, in_triple_string, Cur, Acc) ->
    scan(Rest, Line, normal, Cur, Acc);
%% Newline in triple string
scan([$\n | Rest], Line, in_triple_string, Cur, Acc) ->
    scan(Rest, Line + 1, in_triple_string, Cur, Acc);
%% Any char in triple string
scan([_ | Rest], Line, in_triple_string, Cur, Acc) ->
    scan(Rest, Line, in_triple_string, Cur, Acc);

%% === In block comment ===

%% End of block comment: |#
scan([$|, $# | Rest], Line, in_block_comment, Cur, Acc) ->
    Text = lists:reverse([$#, $| | Cur]),
    StartLine = Line - count_newlines_in(Text),
    scan(Rest, Line, normal, [], [{StartLine, Text, block} | Acc]);
%% Newline in block comment
scan([$\n | Rest], Line, in_block_comment, Cur, Acc) ->
    scan(Rest, Line + 1, in_block_comment, [$\n | Cur], Acc);
%% Any char in block comment
scan([C | Rest], Line, in_block_comment, Cur, Acc) ->
    scan(Rest, Line, in_block_comment, [C | Cur], Acc).

%% === Helpers ===

collect_line_comment(Chars) ->
    collect_line_comment(Chars, []).

collect_line_comment([], Acc) ->
    {lists:reverse(Acc), []};
collect_line_comment([$\n | Rest], Acc) ->
    {lists:reverse(Acc), [$\n | Rest]};
collect_line_comment([C | Rest], Acc) ->
    collect_line_comment(Rest, [C | Acc]).

%% Skip through interpolation #{...} handling nested braces
skip_interp([$} | Rest], Line, 0) ->
    {Rest, Line};
skip_interp([${ | Rest], Line, Depth) ->
    skip_interp(Rest, Line, Depth + 1);
skip_interp([$} | Rest], Line, Depth) ->
    skip_interp(Rest, Line, Depth - 1);
skip_interp([$\n | Rest], Line, Depth) ->
    skip_interp(Rest, Line + 1, Depth);
skip_interp([_ | Rest], Line, Depth) ->
    skip_interp(Rest, Line, Depth);
skip_interp([], Line, _Depth) ->
    {[], Line}.

count_newlines_in(Str) ->
    length([C || C <- Str, C =:= $\n]).

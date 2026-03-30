%% winn_newline_filter.erl
%% Post-lexer token filter for significant newlines.
%%
%% Pass 1: Suppress newlines inside brackets, after operators, collapse duplicates.
%% Pass 2: Inject do/end around multi-expression switch/rescue clause bodies.

-module(winn_newline_filter).
-export([filter/1]).

filter(Tokens) ->
    %% Pass 2 first: inject do/end for multi-expression switch/rescue bodies
    %% (needs newline tokens to detect clause boundaries)
    T1 = pass2_inject_do_end(Tokens),
    %% Pass 1: strip all remaining newlines
    T2 = pass1_basic(T1),
    T2.

%% ── Pass 1: Basic newline filtering ─────────────────────────────────────────
%% - Suppress newlines inside brackets (depth > 0)
%% - Keep newlines only after "expression enders"
%% - Collapse consecutive newlines
%% - Strip leading/trailing newlines

pass1_basic(Tokens) ->
    %% Strip ALL newline tokens. The parser doesn't need them — it uses
    %% keyword boundaries (end, else, rescue, etc.) to delimit expressions.
    %% Pass 2 handles multi-expression switch/rescue bodies via do/end injection.
    [T || T <- Tokens, not is_newline(T)].

is_newline({newline, _}) -> true;
is_newline(_)            -> false.

%% ── Pass 2: Inject do/end for multi-expression switch/rescue clause bodies ──
%% When inside a switch or rescue block and '=>' is NOT followed by 'do',
%% collect the clause body. If it contains newlines, wrap in do/end.

pass2_inject_do_end(Tokens) ->
    pass2(Tokens, [], []).

%% pass2(Remaining, ContextStack, Acc)
%% ContextStack tracks: [switch|rescue|other, ...]

pass2([], _Ctx, Acc) ->
    lists:reverse(Acc);

%% Enter switch context
pass2([{switch, _} = Tok | Rest], Ctx, Acc) ->
    pass2(Rest, [switch | Ctx], [Tok | Acc]);

%% Enter rescue context
pass2([{rescue, _} = Tok | Rest], Ctx, Acc) ->
    pass2(Rest, [rescue | Ctx], [Tok | Acc]);

%% Enter other keyword contexts (if, try, match, fn, for, def) that have 'end'
pass2([{T, _} = Tok | Rest], Ctx, Acc)
  when T =:= 'if'; T =:= 'try'; T =:= 'match'; T =:= 'fn';
       T =:= 'for'; T =:= 'def'; T =:= 'do' ->
    pass2(Rest, [other | Ctx], [Tok | Acc]);

%% Pop context on 'end'
pass2([{'end', _} = Tok | Rest], [_ | Ctx], Acc) ->
    pass2(Rest, Ctx, [Tok | Acc]);
pass2([{'end', _} = Tok | Rest], [], Acc) ->
    pass2(Rest, [], [Tok | Acc]);

%% '=>' in switch/rescue context, NOT followed by 'do' — potential injection point
pass2([{'=>', L} = Arrow | Rest], [InCtx | _] = Ctx, Acc)
  when InCtx =:= switch; InCtx =:= rescue ->
    case Rest of
        [{'do', _} | _] ->
            %% Already has do...end, pass through
            pass2(Rest, Ctx, [Arrow | Acc]);
        _ ->
            %% Collect clause body tokens
            {BodyTokens, Remaining} = collect_clause_body(Rest, 0, []),
            HasNewline = lists:any(fun is_newline/1, BodyTokens),
            case HasNewline of
                true ->
                    %% Multi-expression body — inject do/end, strip newlines from body
                    CleanBody = [T || T <- BodyTokens, not is_newline(T)],
                    pass2(Remaining, Ctx,
                          [{'end', L}] ++ lists:reverse(CleanBody) ++ [{'do', L}, Arrow | Acc]);
                false ->
                    %% Single expression — leave as-is
                    pass2(Remaining, Ctx,
                          lists:reverse(BodyTokens) ++ [Arrow | Acc])
            end
    end;

%% Any other token
pass2([Tok | Rest], Ctx, Acc) ->
    pass2(Rest, Ctx, [Tok | Acc]).

%% Collect tokens for a clause body. The body ends when we see:
%% - A newline followed by a token that could start a new clause pattern,
%%   and that pattern line eventually has '=>' (look-ahead for clause boundary)
%% - 'end' at nesting depth 0 (end of switch/rescue/try)
%% - 'rescue' at depth 0 (transition from try body to rescue)
collect_clause_body([], _Depth, Acc) ->
    {lists:reverse(Acc), []};

%% 'end' at depth 0 — body is done, don't consume the 'end'
collect_clause_body([{'end', _} | _] = Rest, 0, Acc) ->
    {lists:reverse(Acc), Rest};

%% 'rescue' at depth 0 — body done
collect_clause_body([{'rescue', _} | _] = Rest, 0, Acc) ->
    {lists:reverse(Acc), Rest};

%% Newline — check if next tokens start a new clause
collect_clause_body([{newline, _} = NL | Rest], 0, Acc) ->
    case starts_new_clause(Rest) of
        true ->
            %% This newline ends the current clause body
            {lists:reverse(Acc), Rest};
        false ->
            %% Newline is within the clause body (between expressions)
            collect_clause_body(Rest, 0, [NL | Acc])
    end;

%% Track nesting inside body (nested switch/if/try/etc)
collect_clause_body([{T, _} = Tok | Rest], Depth, Acc)
  when T =:= 'switch'; T =:= 'if'; T =:= 'try'; T =:= 'match';
       T =:= 'fn'; T =:= 'for'; T =:= 'do' ->
    collect_clause_body(Rest, Depth + 1, [Tok | Acc]);
collect_clause_body([{'end', _} = Tok | Rest], Depth, Acc) when Depth > 0 ->
    collect_clause_body(Rest, Depth - 1, [Tok | Acc]);

%% Any other token in body
collect_clause_body([Tok | Rest], Depth, Acc) ->
    collect_clause_body(Rest, Depth, [Tok | Acc]).

%% Check if the remaining tokens start a new switch/rescue clause.
%% A new clause looks like: pattern ... '=>' (scan for '=>' before next newline)
starts_new_clause([]) -> false;
starts_new_clause([{'end', _} | _]) -> true;  % end of switch = boundary
starts_new_clause([{'rescue', _} | _]) -> true;
starts_new_clause(Tokens) ->
    has_arrow_before_newline(Tokens).

has_arrow_before_newline([]) -> false;
has_arrow_before_newline([{'=>', _} | _]) -> true;
has_arrow_before_newline([{newline, _} | _]) -> false;
has_arrow_before_newline([_ | Rest]) -> has_arrow_before_newline(Rest).

%% winn_ast.erl
%% Utilities for working with the Winn AST.
%%
%% The AST uses tagged tuples — no records required. Convention:
%%   {Tag, Line, ...fields}
%%
%% This module provides accessors, a pretty-printer, and basic traversal.

-module(winn_ast).
-export([
    line/1,
    tag/1,
    pp/1,
    pp/2,
    walk/2
]).

%% Extract the source line from any AST node.
line({_, Line, _})    when is_integer(Line) -> Line;
line({_, Line, _, _}) when is_integer(Line) -> Line;
line({_, Line, _, _, _}) when is_integer(Line) -> Line;
line({_, Line})       when is_integer(Line) -> Line;
line(_)                                     -> 0.

%% Extract the tag (first element) of an AST node.
tag(Node) when is_tuple(Node) -> element(1, Node);
tag(_)                        -> unknown.

%% Pretty-print an AST to stdout.
pp(Node) -> pp(Node, 0).

pp({module, _L, Name, Body}, Indent) ->
    pad(Indent), io:format("module ~p~n", [Name]),
    [pp(F, Indent + 2) || F <- Body],
    pad(Indent), io:format("end~n", []);

pp({function, _L, Name, Params, Body}, Indent) ->
    ParamStr = string:join([atom_to_list(N) || {var, _, N} <- Params], ", "),
    pad(Indent), io:format("def ~p(~s)~n", [Name, ParamStr]),
    [pp(E, Indent + 2) || E <- Body],
    pad(Indent), io:format("end~n", []);

pp({pipe, _L, Lhs, Rhs}, Indent) ->
    pp(Lhs, Indent),
    pad(Indent), io:format("|>~n", []),
    pp(Rhs, Indent + 2);

pp({call, _L, Fun, Args}, Indent) ->
    ArgStr = pp_args(Args),
    pad(Indent), io:format("~p(~s)~n", [Fun, ArgStr]);

pp({dot_call, _L, Mod, Fun, Args}, Indent) ->
    ArgStr = pp_args(Args),
    pad(Indent), io:format("~p.~p(~s)~n", [Mod, Fun, ArgStr]);

pp({op, _L, Op, Lhs, Rhs}, Indent) ->
    pad(Indent), io:format("(~n", []),
    pp(Lhs, Indent + 2),
    pad(Indent + 2), io:format("~p~n", [Op]),
    pp(Rhs, Indent + 2),
    pad(Indent), io:format(")~n", []);

pp({var, _L, Name}, Indent) ->
    pad(Indent), io:format("~p~n", [Name]);

pp({string, _L, Val}, Indent) ->
    pad(Indent), io:format("~p~n", [Val]);

pp({integer, _L, Val}, Indent) ->
    pad(Indent), io:format("~p~n", [Val]);

pp({float, _L, Val}, Indent) ->
    pad(Indent), io:format("~p~n", [Val]);

pp({atom, _L, Val}, Indent) ->
    pad(Indent), io:format(":~p~n", [Val]);

pp({boolean, _L, Val}, Indent) ->
    pad(Indent), io:format("~p~n", [Val]);

pp({nil, _L}, Indent) ->
    pad(Indent), io:format("nil~n", []);

pp(Other, Indent) ->
    pad(Indent), io:format("~p~n", [Other]).

pp_args([]) -> "";
pp_args(Args) ->
    string:join([io_lib:format("~p", [A]) || A <- Args], ", ").

pad(N) ->
    io:put_chars(lists:duplicate(N, $\s)).

%% Walk an AST, applying a function to every node.
%% Fun/1 receives each node and returns the transformed node.
walk(Fun, {module, L, Name, Body}) ->
    Fun({module, L, Name, [walk(Fun, F) || F <- Body]});
walk(Fun, {function, L, Name, Params, Body}) ->
    Fun({function, L, Name, Params, [walk(Fun, E) || E <- Body]});
walk(Fun, {pipe, L, Lhs, Rhs}) ->
    Fun({pipe, L, walk(Fun, Lhs), walk(Fun, Rhs)});
walk(Fun, {call, L, F, Args}) ->
    Fun({call, L, F, [walk(Fun, A) || A <- Args]});
walk(Fun, {dot_call, L, Mod, F, Args}) ->
    Fun({dot_call, L, Mod, F, [walk(Fun, A) || A <- Args]});
walk(Fun, {op, L, Op, Lhs, Rhs}) ->
    Fun({op, L, Op, walk(Fun, Lhs), walk(Fun, Rhs)});
walk(Fun, {unary, L, Op, Expr}) ->
    Fun({unary, L, Op, walk(Fun, Expr)});
walk(Fun, {assign, L, Pat, Expr}) ->
    Fun({assign, L, Pat, walk(Fun, Expr)});
walk(Fun, {list, L, Elems}) ->
    Fun({list, L, [walk(Fun, E) || E <- Elems]});
walk(Fun, {tuple, L, Elems}) ->
    Fun({tuple, L, [walk(Fun, E) || E <- Elems]});
walk(Fun, Node) ->
    Fun(Node).

%% Winn Language Lexer
%% Tokenizes .winn source files using leex.
%% Newlines are treated as whitespace (not significant) in Phase 1.

Definitions.

D   = [0-9]
A   = [a-zA-Z_]
AN  = [a-zA-Z0-9_]
UC  = [A-Z]
WS  = [\s\t\r\n]

Rules.

%% Whitespace (including newlines — not significant in Phase 1)
{WS}+                       : skip_token.

%% Line comments
#[^\n]*                     : skip_token.

%% Two-character operators (must be before single-char operators)
\|>                         : {token, {'|>', TokenLine}}.
=>                          : {token, {'=>', TokenLine}}.
->                          : {token, {'->', TokenLine}}.
<>                          : {token, {'<>', TokenLine}}.
==                          : {token, {'==', TokenLine}}.
!=                          : {token, {'!=', TokenLine}}.
<=                          : {token, {'<=', TokenLine}}.
>=                          : {token, {'>=', TokenLine}}.
\.\.                        : {token, {'..', TokenLine}}.

%% Keywords — must appear before the identifier catch-all
module                      : {token, {'module', TokenLine}}.
def                         : {token, {'def', TokenLine}}.
do                          : {token, {'do', TokenLine}}.
end                         : {token, {'end', TokenLine}}.
match                       : {token, {'match', TokenLine}}.
ok                          : {token, {'ok_kw', TokenLine}}.
err                         : {token, {'err_kw', TokenLine}}.
true                        : {token, {boolean_lit, TokenLine, true}}.
false                       : {token, {boolean_lit, TokenLine, false}}.
nil                         : {token, {'nil_kw', TokenLine}}.
if                          : {token, {'if', TokenLine}}.
else                        : {token, {'else', TokenLine}}.
unless                      : {token, {'unless', TokenLine}}.
when                        : {token, {'when', TokenLine}}.
switch                      : {token, {'switch', TokenLine}}.
try                         : {token, {'try', TokenLine}}.
rescue                      : {token, {'rescue', TokenLine}}.
and                         : {token, {'and', TokenLine}}.
or                          : {token, {'or', TokenLine}}.
not                         : {token, {'not', TokenLine}}.
import                      : {token, {'import', TokenLine}}.
use                         : {token, {'use', TokenLine}}.
alias                       : {token, {'alias', TokenLine}}.
schema                      : {token, {'schema', TokenLine}}.
has_many                    : {token, {'has_many', TokenLine}}.
belongs_to                  : {token, {'belongs_to', TokenLine}}.
has_one                     : {token, {'has_one', TokenLine}}.
worker                      : {token, {'worker', TokenLine}}.
genserver                   : {token, {'genserver', TokenLine}}.
timestamps                  : {token, {'timestamps', TokenLine}}.
field                       : {token, {'field', TokenLine}}.
fn                          : {token, {'fn', TokenLine}}.
for                         : {token, {'for', TokenLine}}.
in                          : {token, {'in', TokenLine}}.
from                        : {token, {'from_kw', TokenLine}}.
where                       : {token, {'where_kw', TokenLine}}.
order_by                    : {token, {'order_by', TokenLine}}.
limit                       : {token, {'limit_kw', TokenLine}}.
offset                      : {token, {'offset_kw', TokenLine}}.
preload                     : {token, {'preload', TokenLine}}.

%% Atom literals (:foo)
:{A}{AN}*                   : {token, {atom_lit, TokenLine, list_to_atom(tl(TokenChars))}}.

%% Float (before integer to handle 3.14 correctly)
{D}+\.{D}+                  : {token, {float_lit, TokenLine, list_to_float(TokenChars)}}.

%% Integer
{D}+                        : {token, {integer_lit, TokenLine, list_to_integer(TokenChars)}}.

%% String literal (double-quoted, supports #{expr} interpolation)
\"[^\"]*\"                  : make_string_token(TokenLine, TokenChars).

%% Uppercase identifier = module name reference (Blog, IO, String, etc.)
{UC}{AN}*                   : {token, {module_name, TokenLine, list_to_atom(TokenChars)}}.

%% Lowercase/underscore identifier = variable or local function call
%% Allows trailing ? for predicate functions (contains?, valid?, etc.)
{A}{AN}*\?                  : {token, {ident, TokenLine, list_to_atom(TokenChars)}}.
{A}{AN}*                    : {token, {ident, TokenLine, list_to_atom(TokenChars)}}.

%% Single-character comparison operators
<                           : {token, {'<', TokenLine}}.
>                           : {token, {'>', TokenLine}}.

%% Arithmetic operators
\+                          : {token, {'+', TokenLine}}.
-                           : {token, {'-', TokenLine}}.
\*                          : {token, {'*', TokenLine}}.
/                           : {token, {'/', TokenLine}}.

%% Assignment / pattern match operator
=                           : {token, {'=', TokenLine}}.

%% Punctuation
\.                          : {token, {'.', TokenLine}}.
,                           : {token, {',', TokenLine}}.
:                           : {token, {':', TokenLine}}.
\|                          : {token, {'|', TokenLine}}.
\%                          : {token, {'%', TokenLine}}.
\(                          : {token, {'(', TokenLine}}.
\)                          : {token, {')', TokenLine}}.
\[                          : {token, {'[', TokenLine}}.
\]                          : {token, {']', TokenLine}}.
\{                          : {token, {'{', TokenLine}}.
\}                          : {token, {'}', TokenLine}}.
_                           : {token, {'_', TokenLine}}.

Erlang code.

%% String token constructor — detects interpolation.
make_string_token(Line, Chars) ->
    Inner = lists:sublist(Chars, 2, length(Chars) - 2),
    case has_interpolation(Inner) of
        false ->
            {token, {string_lit, Line, list_to_binary(unescape(Inner))}};
        true ->
            Parts = parse_interp(Inner, [], []),
            {token, {interp_string, Line, Parts}}
    end.

has_interpolation([]) -> false;
has_interpolation([$\\, $# | Rest]) -> has_interpolation(Rest);
has_interpolation([$#, ${ | _]) -> true;
has_interpolation([_ | Rest]) -> has_interpolation(Rest).

%% Parse interpolated string into [{str, Binary} | {expr, String}] parts.
parse_interp([], [], Acc) ->
    lists:reverse(Acc);
parse_interp([], Cur, Acc) ->
    lists:reverse([{str, list_to_binary(unescape(lists:reverse(Cur)))} | Acc]);
parse_interp([$\\, $# | Rest], Cur, Acc) ->
    parse_interp(Rest, [$# | Cur], Acc);
parse_interp([$#, ${ | Rest], Cur, Acc) ->
    Acc2 = case Cur of
        [] -> Acc;
        _  -> [{str, list_to_binary(unescape(lists:reverse(Cur)))} | Acc]
    end,
    {ExprChars, Rest2} = extract_interp_expr(Rest, 0, []),
    parse_interp(Rest2, [], [{expr, ExprChars} | Acc2]);
parse_interp([C | Rest], Cur, Acc) ->
    parse_interp(Rest, [C | Cur], Acc).

%% Extract characters inside #{...}, handling nested braces.
extract_interp_expr([$} | Rest], 0, Acc) ->
    {lists:reverse(Acc), Rest};
extract_interp_expr([${ | Rest], Depth, Acc) ->
    extract_interp_expr(Rest, Depth + 1, [${ | Acc]);
extract_interp_expr([$} | Rest], Depth, Acc) ->
    extract_interp_expr(Rest, Depth - 1, [$} | Acc]);
extract_interp_expr([C | Rest], Depth, Acc) ->
    extract_interp_expr(Rest, Depth, [C | Acc]).

unescape([]) -> [];
unescape([$\\, $n  | Rest]) -> [$\n | unescape(Rest)];
unescape([$\\, $t  | Rest]) -> [$\t | unescape(Rest)];
unescape([$\\, $r  | Rest]) -> [$\r | unescape(Rest)];
unescape([$\\, $\\ | Rest]) -> [$\\ | unescape(Rest)];
unescape([$\\, $"  | Rest]) -> [$"  | unescape(Rest)];
unescape([C        | Rest]) -> [C   | unescape(Rest)].

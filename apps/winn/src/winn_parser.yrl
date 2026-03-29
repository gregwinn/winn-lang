%% Winn Language Parser — Phase 2
%% Adds: patterns in function params, multi-clause functions, match...end blocks.
%%
%% Precedence hierarchy (explicit grammar levels, no yecc prec declarations):
%%   pipe  |>
%%   or
%%   and
%%   not  (unary)
%%   ==  !=  <  >  <=  >=
%%   +  -  <>
%%   *  /
%%   unary -
%%   primary (calls, literals, parens, match blocks)

Nonterminals
    program
    top_forms top_form
    module_def module_body dotted_name
    use_directive import_directive alias_directive
    function_def param_list pattern_list
    expr_seq
    expr
    pipe_expr or_expr and_expr not_expr
    cmp_expr add_expr mul_expr unary_expr
    primary_expr
    block_call block_params block_param_list
    call_expr local_call dot_call
    arg_list args
    literal
    list_lit tuple_lit map_lit map_pairs map_pair
    pattern pattern_elems
    match_expr match_clauses match_clause_body match_clause
    if_expr switch_expr switch_clauses switch_clause
    try_expr rescue_clauses rescue_clause_list rescue_clause
    fn_expr for_expr
    schema_def field_list field_item.

%% Phase 1 terminals + Phase 2 additions.
Terminals
    'module' 'def' 'do' 'end' 'use' 'import' 'alias' 'schema' 'field'
    'match' 'ok_kw' 'err_kw' 'nil_kw'
    'if' 'else' 'switch' 'when' 'try' 'rescue'
    'fn' 'for' 'in'
    'and' 'or' 'not'
    ident module_name
    atom_lit integer_lit float_lit string_lit interp_string boolean_lit
    '|>' '|>=' '=>' '..'
    '<>'
    '==' '!='
    '<=' '>='
    '<' '>'
    '+' '-' '*' '/'
    '=' '.' ',' ':' '|'
    '%'
    '(' ')' '[' ']' '{' '}'.

Rootsymbol program.

%% ── Top-level ──────────────────────────────────────────────────────────────

program -> top_forms : '$1'.

top_forms -> '$empty' : [].
top_forms -> top_form top_forms : ['$1' | '$2'].

top_form -> module_def : '$1'.

%% ── Module ─────────────────────────────────────────────────────────────────

module_def -> 'module' dotted_name module_body 'end'
    : {module, line('$1'), '$2', '$3'}.

dotted_name -> module_name                    : val('$1').
dotted_name -> module_name '.' dotted_name    :
    list_to_atom(atom_to_list(val('$1')) ++ "." ++ atom_to_list('$3')).

module_body -> '$empty' : [].
module_body -> function_def module_body : ['$1' | '$2'].
module_body -> use_directive module_body : ['$1' | '$2'].
module_body -> import_directive module_body : ['$1' | '$2'].
module_body -> alias_directive module_body : ['$1' | '$2'].
module_body -> schema_def module_body : ['$1' | '$2'].

%% ── Use directive ────────────────────────────────────────────────────────────

use_directive -> 'use' module_name '.' module_name
    : {use_directive, line('$1'), val('$2'), val('$4')}.

%% ── Import directive ─────────────────────────────────────────────────────────

import_directive -> 'import' module_name
    : {import_directive, line('$1'), val('$2')}.

%% ── Alias directive ──────────────────────────────────────────────────────────

alias_directive -> 'alias' module_name '.' module_name
    : {alias_directive, line('$1'), val('$2'), val('$4')}.

%% ── Function ───────────────────────────────────────────────────────────────

function_def -> 'def' ident '(' param_list ')' expr_seq 'end'
    : {function, line('$1'), val('$2'), '$4', '$6'}.

function_def -> 'def' ident '(' param_list ')' 'when' expr expr_seq 'end'
    : {function_g, line('$1'), val('$2'), '$4', '$7', '$8'}.

param_list -> '$empty'       : [].
param_list -> pattern_list   : '$1'.

pattern_list -> pattern                      : ['$1'].
pattern_list -> pattern ',' pattern_list     : ['$1' | '$3'].

%% ── Expression sequence ────────────────────────────────────────────────────
%% Right-recursive; the last expression is the return value.
%% Stops when it sees 'end', 'ok_kw', 'err_kw' (none can start an expr).

expr_seq -> '$empty'      : [].
expr_seq -> expr expr_seq : ['$1' | '$2'].

%% ── Expression hierarchy ───────────────────────────────────────────────────

expr -> pipe_expr : '$1'.

pipe_expr -> or_expr                       : '$1'.
pipe_expr -> pipe_expr '|>' or_expr
    : {pipe, line('$2'), '$1', '$3'}.
pipe_expr -> pipe_expr '|>=' ident
    : {assign, line('$2'), {var, line('$3'), val('$3')}, '$1'}.

or_expr -> and_expr                        : '$1'.
or_expr -> or_expr 'or' and_expr
    : {op, line('$2'), 'or', '$1', '$3'}.

and_expr -> not_expr                       : '$1'.
and_expr -> and_expr 'and' not_expr
    : {op, line('$2'), 'and', '$1', '$3'}.

not_expr -> cmp_expr                       : '$1'.
not_expr -> 'not' not_expr
    : {unary, line('$1'), 'not', '$2'}.

cmp_expr -> add_expr                       : '$1'.
cmp_expr -> cmp_expr '==' add_expr  : {op, line('$2'), '==', '$1', '$3'}.
cmp_expr -> cmp_expr '!=' add_expr  : {op, line('$2'), '!=', '$1', '$3'}.
cmp_expr -> cmp_expr '<'  add_expr  : {op, line('$2'), '<',  '$1', '$3'}.
cmp_expr -> cmp_expr '>'  add_expr  : {op, line('$2'), '>',  '$1', '$3'}.
cmp_expr -> cmp_expr '<=' add_expr  : {op, line('$2'), '<=', '$1', '$3'}.
cmp_expr -> cmp_expr '>=' add_expr  : {op, line('$2'), '>=', '$1', '$3'}.

add_expr -> mul_expr                       : '$1'.
add_expr -> add_expr '+' mul_expr   : {op, line('$2'), '+',  '$1', '$3'}.
add_expr -> add_expr '-' mul_expr   : {op, line('$2'), '-',  '$1', '$3'}.
add_expr -> add_expr '<>' mul_expr  : {op, line('$2'), '<>', '$1', '$3'}.
add_expr -> add_expr '..' mul_expr : {range, line('$2'), '$1', '$3'}.

mul_expr -> unary_expr                     : '$1'.
mul_expr -> mul_expr '*' unary_expr : {op, line('$2'), '*', '$1', '$3'}.
mul_expr -> mul_expr '/' unary_expr : {op, line('$2'), '/', '$1', '$3'}.

unary_expr -> primary_expr                 : '$1'.
unary_expr -> '-' unary_expr
    : {unary, line('$1'), '-', '$2'}.

%% ── Primary expressions ────────────────────────────────────────────────────

primary_expr -> call_expr                  : '$1'.
primary_expr -> block_call                 : '$1'.
primary_expr -> ident                      : {var, line('$1'), val('$1')}.
primary_expr -> module_name                : {atom, line('$1'), val('$1')}.
primary_expr -> ident '.' ident            : {field_access, line('$2'), {var, line('$1'), val('$1')}, val('$3')}.
primary_expr -> literal                    : '$1'.
primary_expr -> '(' expr ')'               : '$2'.
primary_expr -> match_expr                 : '$1'.
primary_expr -> if_expr                    : '$1'.
primary_expr -> switch_expr                : '$1'.
primary_expr -> try_expr                   : '$1'.
primary_expr -> fn_expr                    : '$1'.
primary_expr -> for_expr                   : '$1'.

%% Assignment: x = expr (parsed at statement level via primary_expr)
primary_expr -> ident '=' expr
    : {assign, line('$2'), {var, line('$1'), val('$1')}, '$3'}.

%% Pattern assignment: {:ok, x} = expr
primary_expr -> '{' arg_list '}' '=' expr
    : {pat_assign, line('$4'), {tuple, line('$1'), '$2'}, '$5'}.

%% ── Match expression ───────────────────────────────────────────────────────
%%
%% Two forms:
%%   1. `match clauses end`          — used as RHS of pipe (scrutinee from pipe)
%%   2. `match or_expr clauses end`  — standalone with explicit scrutinee
%%
%% Disambiguation: if next token after 'match' is ok_kw/err_kw → form 1.
%%                 Otherwise → form 2.

match_expr -> 'match' match_clauses 'end'
    : {match_block, line('$1'), none, '$2'}.

match_expr -> 'match' or_expr match_clauses 'end'
    : {match_block, line('$1'), '$2', '$3'}.

match_clauses -> match_clause                   : ['$1'].
match_clauses -> match_clause match_clauses     : ['$1' | '$2'].

%% Match clause body: one or more expressions separated by whatever follows.
%% expr_seq stops when lookahead is ok_kw, err_kw, or end.
match_clause -> 'ok_kw' pattern '=>' match_clause_body
    : {match_clause, line('$1'), ok, '$2', '$4'}.
match_clause -> 'err_kw' pattern '=>' match_clause_body
    : {match_clause, line('$1'), err, '$2', '$4'}.

%% A clause body is a non-empty expression sequence.
match_clause_body -> expr expr_seq : ['$1' | '$2'].

%% ── Function calls ─────────────────────────────────────────────────────────

call_expr -> local_call : '$1'.
call_expr -> dot_call   : '$1'.

local_call -> ident '(' arg_list ')'
    : {call, line('$1'), val('$1'), '$3'}.

dot_call -> module_name '.' ident '(' arg_list ')'
    : {dot_call, line('$1'), val('$1'), val('$3'), '$5'}.

dot_call -> ident '.' ident '(' arg_list ')'
    : {dot_call, line('$1'), val('$1'), val('$3'), '$5'}.

%% ── Block calls ──────────────────────────────────────────────────────────

block_call -> call_expr 'do' block_params expr_seq 'end'
    : {block_call, line('$2'), '$1', '$3', '$4'}.

block_params -> '$empty'                             : [].
block_params -> '|' '|'                              : [].
block_params -> '|' block_param_list '|'             : '$2'.

block_param_list -> ident                            : [{var, line('$1'), val('$1')}].
block_param_list -> ident ',' block_param_list       : [{var, line('$1'), val('$1')} | '$3'].

arg_list -> '$empty' : [].
arg_list -> args     : '$1'.

args -> expr            : ['$1'].
args -> expr ',' args   : ['$1' | '$3'].

%% ── Literals ───────────────────────────────────────────────────────────────

literal -> integer_lit  : {integer, line('$1'), val('$1')}.
literal -> float_lit    : {float,   line('$1'), val('$1')}.
literal -> string_lit   : {string,  line('$1'), val('$1')}.
literal -> interp_string : {interp_string, line('$1'), val('$1')}.
literal -> atom_lit     : {atom,    line('$1'), val('$1')}.
literal -> boolean_lit  : {boolean, line('$1'), val('$1')}.
literal -> 'nil_kw'     : {nil,     line('$1')}.
literal -> list_lit     : '$1'.
literal -> tuple_lit    : '$1'.
literal -> map_lit      : '$1'.

list_lit  -> '[' arg_list ']'    : {list,  line('$1'), '$2'}.
tuple_lit -> '{' arg_list '}'    : {tuple, line('$1'), '$2'}.

map_lit -> '%' '{' map_pairs '}' : {map, line('$1'), '$3'}.
map_lit -> '%' '{' '}'           : {map, line('$1'), []}.

map_pairs -> map_pair                   : ['$1'].
map_pairs -> map_pair ',' map_pairs     : ['$1' | '$3'].

map_pair -> atom_lit ':' expr : {val('$1'), '$3'}.
map_pair -> ident    ':' expr : {val('$1'), '$3'}.

%% ── Patterns ───────────────────────────────────────────────────────────────
%%
%% Used in function params and match clause patterns.
%% Variable patterns use {var,...} (same as Phase 1) for backward compat.
%% Complex patterns use {pat_*,...} nodes.

pattern -> ident
    : case val('$1') of
          '_' -> {pat_wildcard, line('$1')};
          N   -> {var, line('$1'), N}
      end.

pattern -> atom_lit
    : {pat_atom, line('$1'), val('$1')}.

pattern -> integer_lit
    : {pat_integer, line('$1'), val('$1')}.

pattern -> '-' integer_lit
    : {pat_integer, line('$1'), -(val('$2'))}.

pattern -> boolean_lit
    : {pat_atom, line('$1'), val('$1')}.

pattern -> 'nil_kw'
    : {pat_atom, line('$1'), nil}.

%% Tuple pattern: {:ok, val}, {a, b, c}
pattern -> '{' '}'
    : {pat_tuple, line('$1'), []}.
pattern -> '{' pattern_elems '}'
    : {pat_tuple, line('$1'), '$2'}.

%% List patterns
pattern -> '[' ']'
    : {pat_list, line('$1'), [], nil}.
pattern -> '[' pattern_elems ']'
    : {pat_list, line('$1'), '$2', nil}.
pattern -> '[' pattern_elems '|' pattern ']'
    : {pat_list, line('$1'), '$2', '$4'}.

pattern_elems -> pattern                        : ['$1'].
pattern_elems -> pattern ',' pattern_elems      : ['$1' | '$3'].

%% ── If/else expression ───────────────────────────────────────────────────

if_expr -> 'if' expr expr_seq 'else' expr_seq 'end'
    : {if_expr, line('$1'), '$2', '$3', '$5'}.
if_expr -> 'if' expr expr_seq 'end'
    : {if_expr, line('$1'), '$2', '$3', []}.

%% ── Switch expression ───────────────────────────────────────────────────

switch_expr -> 'switch' expr switch_clauses 'end'
    : {switch_expr, line('$1'), '$2', '$3'}.

switch_clauses -> '$empty'
    : [].
switch_clauses -> switch_clause switch_clauses
    : ['$1' | '$2'].

switch_clause -> pattern '=>' expr
    : {switch_clause, line('$2'), '$1', none, ['$3']}.
switch_clause -> pattern '=>' 'do' expr_seq 'end'
    : {switch_clause, line('$2'), '$1', none, '$4'}.
switch_clause -> pattern 'when' expr '=>' expr
    : {switch_clause, line('$1'), '$1', '$3', ['$5']}.
switch_clause -> pattern 'when' expr '=>' 'do' expr_seq 'end'
    : {switch_clause, line('$1'), '$1', '$3', '$6'}.

%% ── Try/rescue expression ───────────────────────────────────────────────

try_expr -> 'try' expr_seq rescue_clauses 'end'
    : {try_expr, line('$1'), '$2', '$3'}.

rescue_clauses -> '$empty'
    : [].
rescue_clauses -> 'rescue' rescue_clause_list
    : '$2'.

rescue_clause_list -> rescue_clause
    : ['$1'].
rescue_clause_list -> rescue_clause rescue_clause_list
    : ['$1' | '$2'].

rescue_clause -> pattern '=>' 'do' expr_seq 'end'
    : {rescue_clause, line('$2'), '$1', '$4'}.
rescue_clause -> pattern '=>' expr
    : {rescue_clause, line('$2'), '$1', ['$3']}.

%% ── Anonymous function (lambda) ───────────────────────────────────────────
%%   fn(x, y) => x + y end
%%   fn() => 42 end

fn_expr -> 'fn' '(' param_list ')' '=>' expr_seq 'end'
    : {block, line('$1'), '$3', '$6'}.

%% ── For comprehension ────────────────────────────────────────────────────
%%   for x in list do body end

for_expr -> 'for' ident 'in' expr 'do' expr_seq 'end'
    : {for_expr, line('$1'), val('$2'), '$4', '$6'}.

%% ── Schema definition ─────────────────────────────────────────────────────

schema_def -> 'schema' string_lit 'do' field_list 'end'
    : {schema_def, line('$1'), val('$2'), '$4'}.

field_list -> '$empty'
    : [].
field_list -> field_item field_list
    : ['$1' | '$2'].

field_item -> 'field' atom_lit ',' atom_lit
    : {field, line('$1'), val('$2'), val('$4')}.

Erlang code.

line({_, L, _}) -> L;
line({_, L})    -> L.

val({_, _, V}) -> V;
val({_, V})    -> V.

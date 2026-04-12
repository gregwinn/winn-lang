%% winn_transform.erl
%% AST lowering and desugaring pass.
%%
%% Phase 1: Desugar pipe chains into nested calls.
%%   a |> b(x) |> c(y)  =>  c(b(a, x), y)
%%
%% Phase 2: Pattern matching support.
%%   - Lift pattern params to case-wrapped function bodies.
%%   - Merge adjacent multi-clause functions (same name + arity) into one.
%%   - Desugar `match...end` blocks:
%%       `expr |> match ok v => body end`  =>  `case expr of {ok, V} -> body end`
%%       `match expr ok v => body end`     =>  `case expr of {ok, V} -> body end`

-module(winn_transform).
-export([transform/1]).

%% ── Entry point ───────────────────────────────────────────────────────────

%% Transform a parsed program (list of top-level forms).
transform(Forms) when is_list(Forms) ->
    lists:map(fun transform_form/1, Forms).

%% ── Top-level forms ────────────────────────────────────────────────────────

transform_form({module, Line, Name, Body0}) ->
    %% Lower `private def` forms to plain `function` forms, capturing
    %% privacy as a list of `{private_marker, L, Name, Arity}` siblings
    %% that the codegen reads to filter exports.
    {Body, PrivateMarkers} = lower_private_fns(Body0),
    %% Separate use, import, alias directives, schema defs, and regular functions.
    {UseDirs, Rest1}    = lists:partition(fun({use_directive,_,_,_}) -> true; (_) -> false end, Body),
    {ImportDirs, Rest2} = lists:partition(fun({import_directive,_,_}) -> true; (_) -> false end, Rest1),
    {AliasDirs, Rest3}  = lists:partition(fun({alias_directive,_,_,_}) -> true; (_) -> false end, Rest2),
    {StructDefs, Rest4} = lists:partition(fun({struct_def,_,_})        -> true; (_) -> false end, Rest3),
    {ProtocolDefs, Rest5} = lists:partition(fun({protocol_def,_,_})  -> true; (_) -> false end, Rest4),
    {ImplDefs, Rest6}   = lists:partition(fun({impl_def,_,_,_})      -> true; (_) -> false end, Rest5),
    {SchemaDefs, Fns}   = lists:partition(fun({schema_def,_,_,_})    -> true; (_) -> false end, Rest6),

    %% Expand use directives.
    Expanded       = [expand_use(ULine, Mod, Sub, Name) || {use_directive, ULine, Mod, Sub} <- UseDirs],
    BehaviourAttrs = [Attr || {behaviour, Attr, _} <- Expanded]
                  ++ [Attr || {behaviour_only, Attr} <- Expanded],
    SyntheticFns   = [Fn   || {behaviour, _, Fn}   <- Expanded],

    %% Expand struct, protocol, impl, and schema defs into generated functions.
    StructFns = [transform_function(F)
                 || F <- lists:append([expand_struct_def(SD, Name) || SD <- StructDefs])],
    ProtocolFns = [transform_function(F)
                   || F <- lists:append([expand_protocol_def(PD, Name) || PD <- ProtocolDefs])],
    ImplFns = [transform_function(F)
               || F <- lists:append([expand_impl_def(ID, Name) || ID <- ImplDefs])],
    SchemaFns = [transform_function(F)
                 || F <- lists:append([expand_schema_def(SD, Name) || SD <- SchemaDefs])],

    %% Expand default parameters into multiple function clauses.
    ExpandedFns = lists:flatmap(fun expand_default_params/1, Fns),

    %% Transform and merge regular functions.
    Pass1  = [transform_function(F) || F <- ExpandedFns],
    Merged = merge_fn_clauses(StructFns ++ ProtocolFns ++ ImplFns ++ SchemaFns ++ Pass1),

    %% Apply import/alias rewrites.
    Imports  = [Mod || {import_directive, _, Mod} <- ImportDirs],
    AliasMap = maps:from_list(
        [{Sub, list_to_atom(atom_to_list(Top) ++ "." ++ atom_to_list(Sub))}
         || {alias_directive, _, Top, Sub} <- AliasDirs]),
    Final = case {Imports, maps:size(AliasMap)} of
        {[], 0} -> Merged;
        _ ->
            LocalFns = sets:from_list(
                [FName || {function, _, FName, _, _} <- Merged]),
            [rewrite_directives(F, Imports, AliasMap, LocalFns) || F <- Merged]
    end,

    {module, Line, Name, BehaviourAttrs ++ SyntheticFns ++ Final ++ PrivateMarkers};
%% ── Agent desugaring ─────────────────────────────────────────────────────
%% An `agent` block is desugared into a module with GenServer infrastructure.
%% The result is fed back into transform_form({module,...}) for normal processing.

transform_form({agent, Line, Name, Items}) ->
    %% 1. Partition items into state declarations and functions
    {StateDefs, AgentFns} = lists:partition(
        fun({state_decl,_,_,_}) -> true; (_) -> false end, Items),

    %% 2. Build default state map
    DefaultState = {map, Line, [{VName, Expr} || {state_decl, _, VName, Expr} <- StateDefs]},

    ModAtom = lower_module_atom(Name),

    %% 3. Generate behaviour attribute
    BehavAttr = {behaviour_attr, Line, gen_server},

    %% 4. Generate start/0 and start/1
    StartFn0 = gen_agent_start(Line, ModAtom, DefaultState),
    StartFn1 = gen_agent_start_with_overrides(Line, ModAtom, DefaultState),

    %% 5. Generate init/1
    InitFn = {function, Line, init, [{var, Line, '__init_state__'}],
              [{tuple, Line, [{atom, Line, ok}, {var, Line, '__init_state__'}]}]},

    %% 6. For each agent function, generate client fn + handle clause
    FnPairs = [gen_agent_fn_pair(F, ModAtom) || F <- AgentFns],
    ClientFns = [C || {C, _} <- FnPairs],
    HandleFns = [H || {_, H} <- FnPairs],

    %% Group handle_call and handle_cast separately so merge_fn_clauses works
    HandleCalls = [H || {function, _, handle_call, _, _} = H <- HandleFns]
              ++ [H || {function_g, _, handle_call, _, _, _} = H <- HandleFns],
    HandleCasts = [H || {function, _, handle_cast, _, _} = H <- HandleFns],

    %% 7. Generate default handle_cast, handle_info, terminate
    DefaultCast = {function, Line, handle_cast, [{var, Line, '__msg__'}, {var, Line, '__agent_state__'}],
                   [{tuple, Line, [{atom, Line, noreply}, {var, Line, '__agent_state__'}]}]},
    DefaultInfo = {function, Line, handle_info, [{var, Line, '__msg__'}, {var, Line, '__agent_state__'}],
                   [{tuple, Line, [{atom, Line, noreply}, {var, Line, '__agent_state__'}]}]},
    DefaultTerm = {function, Line, terminate, [{var, Line, '__reason__'}, {var, Line, '__agent_state__'}],
                   [{atom, Line, ok}]},

    %% 8. Assemble as a module — group same-name functions adjacently for merge
    ModuleBody = [BehavAttr, StartFn0, StartFn1 | ClientFns]
              ++ [InitFn]
              ++ HandleCalls
              ++ HandleCasts ++ [DefaultCast]
              ++ [DefaultInfo, DefaultTerm],
    transform_form({module, Line, Name, ModuleBody});

transform_form(Other) ->
    Other.

%% ── Use directive expansion ──────────────────────────────────────────────

lower_module_atom(Name) when is_atom(Name) ->
    list_to_atom(string:lowercase(atom_to_list(Name))).

expand_use(Line, 'Winn', 'GenServer', ModName) ->
    ModAtom = lower_module_atom(ModName),
    Attr = {behaviour_attr, Line, gen_server},
    StartLink = {function, Line, start_link, [{var, Line, args}],
        [{dot_call, Line, 'GenServer', start_link, [
            {tuple, Line, [{atom, Line, local}, {atom, Line, ModAtom}]},
            {atom, Line, ModAtom},
            {var, Line, args},
            {list, Line, []}
        ]}]},
    {behaviour, Attr, StartLink};
expand_use(Line, 'Winn', 'Supervisor', ModName) ->
    ModAtom = lower_module_atom(ModName),
    Attr = {behaviour_attr, Line, supervisor},
    StartLink = {function, Line, start_link, [{var, Line, args}],
        [{dot_call, Line, 'Supervisor', start_link, [
            {tuple, Line, [{atom, Line, local}, {atom, Line, ModAtom}]},
            {atom, Line, ModAtom},
            {var, Line, args}
        ]}]},
    {behaviour, Attr, StartLink};
expand_use(Line, 'Winn', 'Router', _ModName) ->
    Attr = {behaviour_attr, Line, winn_router},
    {behaviour_only, Attr};
expand_use(Line, 'Winn', 'Application', _ModName) ->
    Attr = {behaviour_attr, Line, application},
    {behaviour_only, Attr};
expand_use(Line, 'Winn', 'WebSocket', _ModName) ->
    Attr = {behaviour_attr, Line, winn_ws_handler},
    {behaviour_only, Attr};
expand_use(Line, 'Winn', 'Task', _ModName) ->
    Attr = {behaviour_attr, Line, winn_task},
    {behaviour_only, Attr};
expand_use(Line, 'Winn', 'Test', _ModName) ->
    Attr = {behaviour_attr, Line, winn_test},
    {behaviour_only, Attr};
expand_use(_Line, 'Winn', 'Schema', _ModName) ->
    {schema_use, none}.

%% ── Agent helper functions ──────────────────────────────────────────────

%% start/0: start with default state, unwrap {:ok, pid} to just pid
gen_agent_start(L, ModAtom, DefaultState) ->
    {function, L, start, [],
     [{pat_assign, L,
         {tuple, L, [{atom, L, ok}, {var, L, '__agent_pid__'}]},
         {dot_call, L, 'GenServer', start, [
             {atom, L, ModAtom},
             DefaultState,
             {list, L, []}
         ]}},
      {var, L, '__agent_pid__'}]}.

%% start/1: merge overrides into defaults, then start
gen_agent_start_with_overrides(L, ModAtom, DefaultState) ->
    {function, L, start, [{var, L, '__overrides__'}],
     [{assign, L, {var, L, '__merged__'},
         {dot_call, L, 'Map', merge, [DefaultState, {var, L, '__overrides__'}]}},
      {pat_assign, L,
         {tuple, L, [{atom, L, ok}, {var, L, '__agent_pid__'}]},
         {dot_call, L, 'GenServer', start, [
             {atom, L, ModAtom},
             {var, L, '__merged__'},
             {list, L, []}
         ]}},
      {var, L, '__agent_pid__'}]}.

%% Generate client function + handle clause for an agent function
gen_agent_fn_pair({agent_fn, L, FnName, Params, Body}, _ModAtom) ->
    gen_sync_pair(L, FnName, Params, Body);
gen_agent_fn_pair({agent_fn_g, L, FnName, Params, Guard, Body}, _ModAtom) ->
    gen_sync_pair_guarded(L, FnName, Params, Guard, Body);
gen_agent_fn_pair({agent_cast_fn, L, FnName, Params, Body}, _ModAtom) ->
    gen_cast_pair(L, FnName, Params, Body).

%% Sync (gen_server:call) — client + handle_call
gen_sync_pair(L, FnName, Params, Body) ->
    ClientFn = gen_client_fn(L, FnName, Params, call),
    HandleFn = gen_handle_call(L, FnName, Params, none, Body),
    {ClientFn, HandleFn}.

gen_sync_pair_guarded(L, FnName, Params, Guard, Body) ->
    ClientFn = gen_client_fn(L, FnName, Params, call),
    HandleFn = gen_handle_call(L, FnName, Params, Guard, Body),
    {ClientFn, HandleFn}.

%% Async (gen_server:cast) — client + handle_cast
gen_cast_pair(L, FnName, Params, Body) ->
    ClientFn = gen_client_fn(L, FnName, Params, cast),
    HandleFn = gen_handle_cast(L, FnName, Params, Body),
    {ClientFn, HandleFn}.

%% Client function: Mod.fn(pid, args...) -> gen_server:call/cast(pid, msg)
gen_client_fn(L, FnName, Params, CallOrCast) ->
    PidVar = {var, L, '__agent_pid__'},
    ClientParams = [PidVar | Params],
    Msg = agent_message(L, FnName, Params),
    GsFn = case CallOrCast of call -> call; cast -> cast end,
    {function, L, FnName, ClientParams,
     [{dot_call, L, 'GenServer', GsFn, [PidVar, Msg]}]}.

%% Build the message tuple/atom for gen_server call/cast
agent_message(L, FnName, []) ->
    {atom, L, FnName};
agent_message(L, FnName, Params) ->
    {tuple, L, [{atom, L, FnName} | Params]}.

%% Build the pattern for matching the message in handle_call/handle_cast
agent_message_pattern(L, FnName, []) ->
    {pat_atom, L, FnName};
agent_message_pattern(L, FnName, Params) ->
    {pat_tuple, L, [{pat_atom, L, FnName} | params_to_patterns(Params)]}.

params_to_patterns(Params) ->
    [case P of
         {var, PL, N} -> {var, PL, N};
         {pat_wildcard, _} = W -> W;
         {pat_var, _, _} = PV -> PV;
         Other -> Other
     end || P <- Params].

%% Generate handle_call clause
gen_handle_call(L, FnName, Params, Guard, Body) ->
    MsgPat = agent_message_pattern(L, FnName, Params),
    {RewrittenBody, _Counter} = rewrite_agent_body(Body, 0),
    %% Extract last expression as reply value, wrap in {:reply, val, state}
    WrappedBody = wrap_reply(L, RewrittenBody),
    case Guard of
        none ->
            {function, L, handle_call,
             [MsgPat, {var, L, '__from__'}, {var, L, '__agent_state__'}],
             WrappedBody};
        _ ->
            {function_g, L, handle_call,
             [MsgPat, {var, L, '__from__'}, {var, L, '__agent_state__'}],
             Guard,
             WrappedBody}
    end.

%% Generate handle_cast clause
gen_handle_cast(L, FnName, Params, Body) ->
    MsgPat = agent_message_pattern(L, FnName, Params),
    {RewrittenBody, _Counter} = rewrite_agent_body(Body, 0),
    %% Wrap in {:noreply, state}
    WrappedBody = wrap_noreply(L, RewrittenBody),
    {function, L, handle_cast,
     [MsgPat, {var, L, '__agent_state__'}],
     WrappedBody}.

%% Wrap body: all exprs, then {:reply, last_value, __agent_state__}
wrap_reply(L, []) ->
    [{tuple, L, [{atom, L, reply}, {atom, L, nil}, {var, L, '__agent_state__'}]}];
wrap_reply(L, Body) ->
    {Init, Last} = split_last(Body),
    Init ++ [
        {assign, L, {var, L, '__agent_reply__'}, Last},
        {tuple, L, [{atom, L, reply}, {var, L, '__agent_reply__'}, {var, L, '__agent_state__'}]}
    ].

%% Wrap body: all exprs, then {:noreply, __agent_state__}
wrap_noreply(L, []) ->
    [{tuple, L, [{atom, L, noreply}, {var, L, '__agent_state__'}]}];
wrap_noreply(L, Body) ->
    Body ++ [
        {tuple, L, [{atom, L, noreply}, {var, L, '__agent_state__'}]}
    ].

split_last([X]) -> {[], X};
split_last([H | T]) ->
    {Rest, Last} = split_last(T),
    {[H | Rest], Last}.

%% ── Agent body rewriting ────────────────────────────────────────────────
%% Rewrites @var reads and @var = expr writes in agent function bodies.

rewrite_agent_body(Exprs, Counter) ->
    {Rewritten, C1} = lists:mapfoldl(fun rewrite_agent_expr/2, Counter, Exprs),
    {flatten_agent_body(Rewritten), C1}.

rewrite_agent_expr({state_read, L, Name}, Counter) ->
    {{field_access, L, {var, L, '__agent_state__'}, Name}, Counter};

rewrite_agent_expr({state_write, L, Name, Expr}, Counter) ->
    {RewrittenExpr, C1} = rewrite_agent_expr(Expr, Counter),
    WVar = list_to_atom("__agent_w" ++ integer_to_list(C1) ++ "__"),
    %% Expand to: __agent_wN__ = expr, __agent_state__ = Map.put(state, :name, wN), __agent_wN__
    Nodes = [
        {assign, L, {var, L, WVar}, RewrittenExpr},
        {assign, L, {var, L, '__agent_state__'},
            {dot_call, L, 'Map', put, [
                {atom, L, Name},
                {var, L, WVar},
                {var, L, '__agent_state__'}
            ]}},
        {var, L, WVar}
    ],
    %% Return the sequence as a special multi-node marker
    {{agent_write_seq, L, Nodes}, C1 + 1};

%% Recurse into nested expressions
rewrite_agent_expr({op, L, Op, Lhs, Rhs}, Counter) ->
    {L2, C1} = rewrite_agent_expr(Lhs, Counter),
    {R2, C2} = rewrite_agent_expr(Rhs, C1),
    {{op, L, Op, L2, R2}, C2};
rewrite_agent_expr({unary, L, Op, E}, Counter) ->
    {E2, C1} = rewrite_agent_expr(E, Counter),
    {{unary, L, Op, E2}, C1};
rewrite_agent_expr({call, L, Fun, Args}, Counter) ->
    {Args2, C1} = rewrite_agent_body(Args, Counter),
    {{call, L, Fun, Args2}, C1};
rewrite_agent_expr({dot_call, L, Mod, Fun, Args}, Counter) ->
    {Args2, C1} = rewrite_agent_body(Args, Counter),
    {{dot_call, L, Mod, Fun, Args2}, C1};
rewrite_agent_expr({assign, L, Var, Expr}, Counter) ->
    {E2, C1} = rewrite_agent_expr(Expr, Counter),
    {{assign, L, Var, E2}, C1};
rewrite_agent_expr({tuple, L, Elems}, Counter) ->
    {E2, C1} = rewrite_agent_body(Elems, Counter),
    {{tuple, L, E2}, C1};
rewrite_agent_expr({list, L, Elems}, Counter) ->
    {E2, C1} = rewrite_agent_body(Elems, Counter),
    {{list, L, E2}, C1};
rewrite_agent_expr({map, L, Pairs}, Counter) ->
    {Vals, C1} = rewrite_agent_body([V || {_, V} <- Pairs], Counter),
    Keys = [K || {K, _} <- Pairs],
    {{map, L, lists:zip(Keys, Vals)}, C1};
rewrite_agent_expr({if_expr, L, Cond, Then, Else}, Counter) ->
    {Cond2, C1} = rewrite_agent_expr(Cond, Counter),
    {Then2, C2} = rewrite_agent_body(Then, C1),
    {Else2, C3} = rewrite_agent_body(Else, C2),
    {{if_expr, L, Cond2, Then2, Else2}, C3};
rewrite_agent_expr({block, L, Params, Body}, Counter) ->
    {Body2, C1} = rewrite_agent_body(Body, Counter),
    {{block, L, Params, Body2}, C1};
rewrite_agent_expr(Other, Counter) ->
    {Other, Counter}.

%% Flatten agent_write_seq nodes into the body list
flatten_agent_body(Exprs) ->
    lists:flatmap(fun({agent_write_seq, _, Nodes}) -> Nodes;
                     (Other) -> [Other]
                  end, Exprs).

%% ── Default parameter expansion ─────────────────────────────────────────
%% Generates wrapper clauses for functions with default parameters.
%% def greet(name, greeting = "Hello") ... end
%% becomes:
%%   def greet(name)           → greet(name, "Hello")
%%   def greet(name, greeting) → <original body>

expand_default_params({function, Line, Name, Params, Body}) ->
    case split_defaults(Params) of
        {_, []} ->
            %% No defaults — return as-is
            [{function, Line, Name, Params, Body}];
        {Required, Defaults} ->
            %% Generate the full-arity clause with plain var params
            FullParams = Required ++ [begin {var, DL, DN} end
                                      || {default_param, DL, DN, _} <- Defaults],
            FullClause = {function, Line, Name, FullParams, Body},
            %% Generate wrapper clauses for each missing default
            Wrappers = generate_default_wrappers(Line, Name, Required, Defaults),
            Wrappers ++ [FullClause]
    end;
expand_default_params(Other) ->
    [Other].

split_defaults(Params) ->
    split_defaults(Params, [], []).
split_defaults([], Req, Def) ->
    {lists:reverse(Req), lists:reverse(Def)};
split_defaults([{default_param, _, _, _} = D | Rest], Req, Def) ->
    split_defaults(Rest, Req, [D | Def]);
split_defaults([P | Rest], Req, Def) ->
    split_defaults(Rest, [P | Req], Def).

generate_default_wrappers(Line, Name, Required, Defaults) ->
    %% For N defaults, generate N wrappers.
    %% Wrapper K takes Required + first K default params, fills in the rest.
    AllDefaults = [{var, DL, DN} || {default_param, DL, DN, _} <- Defaults],
    AllDefaultVals = [DV || {default_param, _, _, DV} <- Defaults],
    NumDefaults = length(Defaults),
    [begin
        %% Take first K default params as explicit args
        ExplicitDefParams = lists:sublist(AllDefaults, K),
        %% Fill remaining defaults with their values
        RemainingVals = lists:nthtail(K, AllDefaultVals),
        WrapperParams = Required ++ ExplicitDefParams,
        CallArgs = Required ++ ExplicitDefParams ++ RemainingVals,
        {function, Line, Name, WrapperParams, [{call, Line, Name, CallArgs}]}
     end || K <- lists:seq(0, NumDefaults - 1)].

%% ── Struct definition expansion ──────────────────────────────────────────
%% defstruct [:name, :email, :age] generates:
%%   __struct__()  -> module atom (for type identification)
%%   __fields__()  -> [:name, :email, :age]
%%   new()         -> %{__struct__: ModName, name: nil, email: nil, age: nil}
%%   new(attrs)    -> Map.merge(new(), attrs)

expand_struct_def({struct_def, L, FieldNames}, ModName) ->
    ModAtom = lower_module_atom(ModName),

    %% __struct__() -> module atom
    StructFn = {function, L, '__struct__', [],
                [{atom, L, ModAtom}]},

    %% __fields__() -> list of field atoms
    FieldsFn = {function, L, '__fields__', [],
                [{list, L, [{atom, L, F} || F <- FieldNames]}]},

    %% Default map: %{__struct__: mod, field1: nil, field2: nil, ...}
    DefaultPairs = [{'__struct__', {atom, L, ModAtom}}
                   | [{F, {nil, L}} || F <- FieldNames]],

    %% new() -> default map
    New0Fn = {function, L, new, [],
              [{map, L, DefaultPairs}]},

    %% new(attrs) -> Map.merge(default, attrs)
    New1Fn = {function, L, new, [{var, L, attrs}],
              [{dot_call, L, 'Map', merge, [
                  {map, L, DefaultPairs},
                  {var, L, attrs}
              ]}]},

    [StructFn, FieldsFn, New0Fn, New1Fn].

%% ── Protocol definition expansion ────────────────────────────────────────
%% protocol do
%%   def to_s(value)
%%     ...
%%   end
%% end
%%
%% Generates dispatch functions:
%%   to_s(value) -> winn_protocol:dispatch(protocol_name, to_s, [value])

expand_protocol_def({protocol_def, L, MethodDefs}, ModName) ->
    ProtocolAtom = lower_module_atom(ModName),
    [begin
        Arity = length(Params),
        DispatchArgs = {list, L, [{var, L, P} || {var, _, P} <- Params]},
        {function, L, FnName, Params,
         [{dot_call, L, 'Protocol', dispatch, [
             {atom, L, ProtocolAtom},
             {atom, L, FnName},
             DispatchArgs
         ]}]}
     end || {function, _, FnName, Params, _} <- MethodDefs,
            Arity <- [length(Params)],
            Arity > 0].

%% ── Implementation definition expansion ─────────────────────────────────
%% impl Printable do
%%   def to_s(user)
%%     "User(#{user.name})"
%%   end
%% end
%%
%% Generates:
%%   '__impl_printable_to_s'/1 — the actual implementation
%%   '__register_impls__'/0 — registers all impls in ETS (called at load time)

expand_impl_def({impl_def, L, ProtocolName, MethodDefs}, ModName) ->
    ProtocolAtom = lower_module_atom(ProtocolName),
    StructAtom = lower_module_atom(ModName),
    ModAtom = lower_module_atom(ModName),

    %% Generate implementation functions with mangled names
    ImplFns = [begin
        ImplName = list_to_atom("__impl_" ++ atom_to_list(ProtocolAtom)
                                ++ "_" ++ atom_to_list(FnName)),
        {function, L, ImplName, Params, Body}
    end || {function, _, FnName, Params, Body} <- MethodDefs],

    %% Generate registration function
    RegCalls = [begin
        ImplName = list_to_atom("__impl_" ++ atom_to_list(ProtocolAtom)
                                ++ "_" ++ atom_to_list(FnName)),
        {dot_call, L, 'Protocol', register_impl, [
            {atom, L, ProtocolAtom},
            {atom, L, FnName},
            {atom, L, StructAtom},
            {tuple, L, [{atom, L, ModAtom}, {atom, L, ImplName}]}
        ]}
    end || {function, _, FnName, _, _} <- MethodDefs],

    RegFn = {function, L, '__register_impls__', [],
             RegCalls ++ [{atom, L, ok}]},

    ImplFns ++ [RegFn].

%% ── Schema definition expansion ──────────────────────────────────────────

expand_schema_def({schema_def, L, TableBin, Fields}, ModName) ->
    ModAtom = lower_module_atom(ModName),

    %% __schema__(:source) -> table name binary
    SourceFn = {function, L, '__schema__', [{pat_atom, L, source}],
                [{string, L, TableBin}]},

    %% __schema__(:fields) -> list of field name atoms
    FieldsFn = {function, L, '__schema__', [{pat_atom, L, fields}],
                [{list, L, [{atom, L, FName} || {field, _, FName, _} <- Fields]}]},

    %% __schema__(:types) -> map of field -> type
    TypesFn = {function, L, '__schema__', [{pat_atom, L, types}],
               [{map, L, [{FName, {atom, L, FType}} || {field, _, FName, FType} <- Fields]}]},

    %% new(attrs) -> Map.merge(%{field: nil,...}, attrs)
    NilFields = [{FName, {nil, L}} || {field, _, FName, _} <- Fields],
    NewFn = {function, L, new, [{var, L, attrs}],
             [{dot_call, L, 'Map', merge, [
                 {map, L, NilFields},
                 {var, L, attrs}
             ]}]},

    %% ── Rails-style model query methods ─────────────────────────────
    %% all()         -> Repo.all(ModName)
    AllFn = {function, L, all, [],
             [{dot_call, L, 'Repo', all, [{atom, L, ModAtom}]}]},

    %% find(id)      -> Repo.get(ModName, id)
    FindFn = {function, L, find, [{var, L, id}],
              [{dot_call, L, 'Repo', get, [{atom, L, ModAtom}, {var, L, id}]}]},

    %% find_by(field, value) -> Repo.get(ModName, field, value)
    FindByFn = {function, L, find_by, [{var, L, field}, {var, L, value}],
                [{dot_call, L, 'Repo', get, [
                    {atom, L, ModAtom}, {var, L, field}, {var, L, value}
                ]}]},

    %% create(attrs)  -> Repo.insert(ModName, attrs)
    CreateFn = {function, L, create, [{var, L, attrs}],
                [{dot_call, L, 'Repo', insert, [{atom, L, ModAtom}, {var, L, attrs}]}]},

    %% delete(record) -> Repo.delete(record)
    DeleteFn = {function, L, delete, [{var, L, record}],
                [{dot_call, L, 'Repo', delete, [{var, L, record}]}]},

    %% count()        -> Repo.count(ModName)
    CountFn = {function, L, count, [],
               [{dot_call, L, 'Repo', count, [{atom, L, ModAtom}]}]},

    [SourceFn, FieldsFn, TypesFn, NewFn,
     AllFn, FindFn, FindByFn, CreateFn, DeleteFn, CountFn].

%% ── Private function lowering ──────────────────────────────────────────────
%% Rewrite each {private_function, ...} (and the guarded variant) to a plain
%% {function, ...} so the rest of the pipeline doesn't need to know about
%% privacy. Privacy is recorded out-of-band as {private_marker, L, Name, Arity}
%% siblings, which winn_codegen reads to filter the export list.

lower_private_fns(Body) ->
    lists:foldr(fun lower_private_one/2, {[], []}, Body).

lower_private_one({private_function, L, Name, Params, FBody}, {Forms, Markers}) ->
    Marker = {private_marker, L, Name, length(Params)},
    {[{function, L, Name, Params, FBody} | Forms], [Marker | Markers]};
lower_private_one({private_function_g, L, Name, Params, Guard, FBody}, {Forms, Markers}) ->
    Marker = {private_marker, L, Name, length(Params)},
    {[{function_g, L, Name, Params, Guard, FBody} | Forms], [Marker | Markers]};
lower_private_one(Other, {Forms, Markers}) ->
    {[Other | Forms], Markers}.

%% ── Function transformation ────────────────────────────────────────────────

%% Pass through non-function nodes (e.g. behaviour_attr from agent desugaring)
transform_function({behaviour_attr, _, _} = B) -> B;

transform_function({function_g, Line, Name, Params, Guard, Body}) ->
    TransBody  = transform_seq(Body),
    TransGuard = transform_expr(Guard),
    Arity   = length(Params),
    ArgVars = fresh_arg_vars(Line, Arity),
    Scrutinee = case Arity of
        1 -> hd(ArgVars);
        _ -> {tuple, Line, ArgVars}
    end,
    CasePat = case Arity of
        1 -> hd(Params);
        _ -> {pat_tuple, Line, Params}
    end,
    CaseClause = {case_clause, Line, [CasePat], TransGuard, TransBody},
    {function, Line, Name, ArgVars, [{case_expr, Line, Scrutinee, [CaseClause]}]};

transform_function({function, Line, Name, Params, Body}) ->
    TransBody = transform_seq(Body),
    %% Always case-wrap so that multi-clause functions (some guarded, some not)
    %% can be merged into a single case expression.
    wrap_in_case(Line, Name, Params, TransBody).

%% Wrap pattern-param function into a case expression.
%%   def foo({:ok, x}) body end
%% becomes:
%%   def foo(_arg0) case _arg0 of {:ok, X} -> body end end
%%
%% For multi-arg functions, scrutinee is a tuple of all args:
%%   def foo(a, {:ok, b}) body end
%% becomes:
%%   def foo(_arg0, _arg1) case {_arg0, _arg1} of {A, {:ok, B}} -> body end end
wrap_in_case(Line, Name, Params, Body) ->
    Arity = length(Params),
    ArgVars = fresh_arg_vars(Line, Arity),
    Scrutinee = case Arity of
        1 -> hd(ArgVars);
        _ -> {tuple, Line, ArgVars}
    end,
    CasePat = case Arity of
        1 -> hd(Params);
        _ -> {pat_tuple, Line, Params}
    end,
    CaseClause = {case_clause, Line, [CasePat], none, Body},
    {function, Line, Name, ArgVars, [{case_expr, Line, Scrutinee, [CaseClause]}]}.

fresh_arg_vars(Line, Arity) ->
    [{var, Line, list_to_atom("_arg" ++ integer_to_list(I))}
     || I <- lists:seq(0, Arity - 1)].

%% ── Multi-clause function merging ─────────────────────────────────────────
%%
%% Adjacent function nodes with the same name and arity are merged into a
%% single function whose body is a case expression with all clauses.
%%
%% Input:
%%   {function, L, foo, [_arg0], [{case_expr, L, _arg0, [Clause1]}]}
%%   {function, L, foo, [_arg0], [{case_expr, L, _arg0, [Clause2]}]}
%%
%% Output:
%%   {function, L, foo, [_arg0], [{case_expr, L, _arg0, [Clause1, Clause2]}]}

merge_fn_clauses([]) ->
    [];
merge_fn_clauses([{function, L, Name, Args, [{case_expr, CL, Scr, Clauses}]} | Rest]) ->
    Arity = length(Args),
    {Same, Remaining} = take_matching_fns(Name, Arity, Rest),
    AllClauses = Clauses ++ lists:append(
        [Cs || {function,_,_,_,[{case_expr,_,_,Cs}]} <- Same]
    ),
    Merged = {function, L, Name, Args, [{case_expr, CL, Scr, AllClauses}]},
    [Merged | merge_fn_clauses(Remaining)];
merge_fn_clauses([F | Rest]) ->
    [F | merge_fn_clauses(Rest)].

%% Take consecutive functions with the same name/arity that are already
%% case-wrapped (so they came from pattern-param defs).
take_matching_fns(Name, Arity,
    [{function,_,Name,Args,[{case_expr,_,_,_}]} = F | Rest])
    when length(Args) =:= Arity ->
    {More, Remaining} = take_matching_fns(Name, Arity, Rest),
    {[F | More], Remaining};
take_matching_fns(_, _, Rest) ->
    {[], Rest}.

%% ── Expression sequences ──────────────────────────────────────────────────

transform_seq(Exprs) ->
    lists:map(fun transform_expr/1, Exprs).

%% ── Expressions ───────────────────────────────────────────────────────────

%% Pipe into a block_call: expr |> foo() do |x| body end
transform_expr({pipe, Line, Lhs, {block_call, BLine, CallExpr, BlockParams, BlockBody}}) ->
    TransLhs  = transform_expr(Lhs),
    TransBody = transform_seq(BlockBody),
    Block     = {block, BLine, BlockParams, TransBody},
    case transform_expr(CallExpr) of
        {call, CLine, Fun, Args} ->
            {call, CLine, Fun, [TransLhs | [transform_expr(A) || A <- Args]] ++ [Block]};
        {dot_call, CLine, Mod, Fun, Args} ->
            {dot_call, CLine, Mod, Fun, [TransLhs | [transform_expr(A) || A <- Args]] ++ [Block]};
        _ ->
            error({unsupported_pipe_block_target, Line})
    end;

%% Standalone block_call: foo() do |x| body end
transform_expr({block_call, Line, CallExpr, BlockParams, BlockBody}) ->
    TransBody = transform_seq(BlockBody),
    Block     = {block, Line, BlockParams, TransBody},
    case transform_expr(CallExpr) of
        {call, CLine, Fun, Args} ->
            {call, CLine, Fun, [transform_expr(A) || A <- Args] ++ [Block]};
        {dot_call, CLine, Mod, Fun, Args} ->
            {dot_call, CLine, Mod, Fun, [transform_expr(A) || A <- Args] ++ [Block]};
        _ ->
            error({unsupported_block_call_target, Line})
    end;

%% Pipe into a match block: `expr |> match clauses end`
%% Desugar to a case expression with the pipe LHS as scrutinee.
transform_expr({pipe, Line, Lhs, {match_block, _, none, Clauses}}) ->
    TransLhs = transform_expr(Lhs),
    TransClauses = [transform_match_clause(C) || C <- Clauses],
    {case_expr, Line, TransLhs, TransClauses};

%% Regular pipe: desugar to nested call.
transform_expr({pipe, Line, Lhs, Rhs}) ->
    TransLhs = transform_expr(Lhs),
    case transform_expr(Rhs) of
        {call, CLine, Fun, Args} ->
            {call, CLine, Fun, [TransLhs | Args]};
        {dot_call, CLine, Mod, Fun, Args} ->
            {dot_call, CLine, Mod, Fun, [TransLhs | Args]};
        Other ->
            %% Non-call RHS — leave as a pipe_apply for error reporting.
            {pipe_apply, Line, TransLhs, Other}
    end;

%% Standalone match block with an explicit scrutinee.
transform_expr({match_block, Line, Scrutinee, Clauses}) when Scrutinee =/= none ->
    TransScrutinee = transform_expr(Scrutinee),
    TransClauses = [transform_match_clause(C) || C <- Clauses],
    {case_expr, Line, TransScrutinee, TransClauses};

%% Standalone match block with no scrutinee — semantic error, pass through.
transform_expr({match_block, Line, none, Clauses}) ->
    TransClauses = [transform_match_clause(C) || C <- Clauses],
    {match_block_no_scrutinee, Line, TransClauses};

%% String interpolation: "Hello #{name}!" => "Hello " <> to_string(name) <> "!"
transform_expr({interp_string, Line, Parts}) ->
    Exprs = lists:map(fun({str, Bin}) ->
                {string, Line, Bin};
            ({expr, ExprStr}) ->
                %% Re-lex and parse the interpolated expression.
                case winn_lexer:string(ExprStr) of
                    {ok, Tokens, _} ->
                        %% Wrap in a dummy module/function for parsing, or parse as expr.
                        %% We parse as a bare expression by wrapping in parens.
                        case winn_parser:parse([{'module',1},
                                                {module_name,1,'_X'},
                                                {'def',1},
                                                {ident,1,x},
                                                {'(',1},{')',1}] ++
                                               Tokens ++
                                               [{'end',1},{'end',1}]) of
                            {ok, [{module,_,'_X',[{function,_,x,[],Body}]}]} ->
                                %% Wrap in to_string call for non-string values.
                                Expr = case Body of
                                    [Single] -> Single;
                                    _ -> hd(Body)
                                end,
                                {dot_call, Line, 'Winn', to_string, [transform_expr(Expr)]};
                            _ ->
                                {string, Line, list_to_binary(ExprStr)}
                        end;
                    _ ->
                        {string, Line, list_to_binary(ExprStr)}
                end
        end, Parts),
    %% Concatenate all parts with <>.
    case Exprs of
        []     -> {string, Line, <<>>};
        [Single] -> Single;
        [First | Rest] ->
            lists:foldl(fun(E, Acc) -> {op, Line, '<>', Acc, E} end, First, Rest)
    end;

%% Recursive cases.
transform_expr({call, Line, Fun, Args}) ->
    {call, Line, Fun, lists:map(fun transform_expr/1, Args)};
transform_expr({dot_call, Line, Mod, Fun, Args}) ->
    {dot_call, Line, Mod, Fun, lists:map(fun transform_expr/1, Args)};
transform_expr({op, Line, Op, Lhs, Rhs}) ->
    {op, Line, Op, transform_expr(Lhs), transform_expr(Rhs)};
transform_expr({unary, Line, Op, Expr}) ->
    {unary, Line, Op, transform_expr(Expr)};
%% For comprehension: for x in list do body end => Enum.map(list) do |x| body end
transform_expr({for_expr, Line, Var, ListExpr, Body}) ->
    TransList = transform_expr(ListExpr),
    TransBody = transform_seq(Body),
    Block = {block, Line, [{var, Line, Var}], TransBody},
    {dot_call, Line, 'Enum', map, [TransList, Block]};

transform_expr({range, Line, From, To}) ->
    {range, Line, transform_expr(From), transform_expr(To)};
transform_expr({field_access, Line, Expr, Field}) ->
    {field_access, Line, transform_expr(Expr), Field};
%% Pattern assignment: {:ok, x} = expr => case expr of {:ok, X} -> {:ok, X} end
%% Desugars to a case expression. Variables bound in the pattern become
%% available in subsequent expressions (handled by gen_body's let scoping).
transform_expr({pat_assign, Line, Pat, Expr}) ->
    TransExpr = transform_expr(Expr),
    %% Convert tuple literal to pattern
    CasePat = lit_to_pat(Pat),
    %% The body returns the matched value so it can be used
    CaseClause = {case_clause, Line, [CasePat], none, [TransExpr]},
    {pat_assign_case, Line, CasePat, {case_expr, Line, TransExpr, [CaseClause]}};

transform_expr({assign, Line, Pat, Expr}) ->
    {assign, Line, Pat, transform_expr(Expr)};
transform_expr({list, Line, Elements}) ->
    {list, Line, lists:map(fun transform_expr/1, Elements)};
transform_expr({tuple, Line, Elements}) ->
    {tuple, Line, lists:map(fun transform_expr/1, Elements)};
transform_expr({map, Line, Pairs}) ->
    {map, Line, [{K, transform_expr(V)} || {K, V} <- Pairs]};

%% Block (closure) — body already transformed above, leave node intact.
transform_expr({block, Line, Params, Body}) ->
    {block, Line, Params, Body};

%% L1 — if/else desugared to case
transform_expr({if_expr, Line, Cond, Then, []}) ->
    TrueClause = {case_clause, Line, [{pat_atom, Line, true}], none, transform_seq(Then)},
    {case_expr, Line, transform_expr(Cond), [TrueClause]};

transform_expr({if_expr, Line, Cond, Then, Else}) ->
    TrueClause  = {case_clause, Line, [{pat_atom, Line, true}], none, transform_seq(Then)},
    FalseClause = {case_clause, Line, [{pat_wildcard, Line}],   none, transform_seq(Else)},
    {case_expr, Line, transform_expr(Cond), [TrueClause, FalseClause]};

%% L2 — switch desugared to case
transform_expr({switch_expr, Line, Scrutinee, Clauses}) ->
    CaseClauses = [{case_clause, CL, [Pat], Guard, transform_seq(Body)}
                   || {switch_clause, CL, Pat, Guard, Body} <- Clauses],
    {case_expr, Line, transform_expr(Scrutinee), CaseClauses};

%% L4 — try/rescue
transform_expr({try_expr, Line, TryBody, RescueClauses}) ->
    TransBody   = transform_seq(TryBody),
    TransRescue = [{rescue_clause, RL, Pat, transform_seq(RBody)}
                   || {rescue_clause, RL, Pat, RBody} <- RescueClauses],
    {try_expr, Line, TransBody, TransRescue};

%% Leaf nodes — no transformation needed.
transform_expr(Leaf) ->
    Leaf.

%% ── Literal to pattern conversion ─────────────────────────────────────────
%% Converts AST expression nodes to pattern nodes for pat_assign.

lit_to_pat({tuple, Line, Elems}) ->
    {pat_tuple, Line, [lit_to_pat(E) || E <- Elems]};
lit_to_pat({list, Line, Elems}) ->
    {pat_list, Line, [lit_to_pat(E) || E <- Elems], nil};
lit_to_pat({atom, Line, V}) ->
    {pat_atom, Line, V};
lit_to_pat({integer, Line, V}) ->
    {pat_integer, Line, V};
lit_to_pat({var, Line, Name}) ->
    {pat_var, Line, Name};
lit_to_pat({pat_wildcard, _} = P) -> P;
lit_to_pat({pat_var, _, _} = P) -> P;
lit_to_pat({pat_atom, _, _} = P) -> P;
lit_to_pat({pat_integer, _, _} = P) -> P;
lit_to_pat({pat_tuple, _, _} = P) -> P;
lit_to_pat({pat_list, _, _, _} = P) -> P;
lit_to_pat(Other) -> Other.

%% ── Match clause desugaring ────────────────────────────────────────────────
%%
%% ok_kw and err_kw are syntactic sugar for {ok, _} and {error, _} patterns.
%%
%%   ok v   =>  pattern: {pat_tuple, [{pat_atom, ok}, {var, v}]}
%%   err e  =>  pattern: {pat_tuple, [{pat_atom, error}, {var, e}]}

transform_match_clause({match_clause, Line, ok, PatternNode, Body}) ->
    OkPat = {pat_tuple, Line, [{pat_atom, Line, ok}, PatternNode]},
    TransBody = transform_seq(Body),
    {case_clause, Line, [OkPat], none, TransBody};
transform_match_clause({match_clause, Line, err, PatternNode, Body}) ->
    ErrPat = {pat_tuple, Line, [{pat_atom, Line, error}, PatternNode]},
    TransBody = transform_seq(Body),
    {case_clause, Line, [ErrPat], none, TransBody}.

%% ── Import/alias rewriting ──────────────────────────────────────────────────
%% Walks the AST and rewrites:
%%   - Local calls to dot calls when the function is imported and not local
%%   - Dot calls with aliased short names to full module names

rewrite_directives({function, Line, Name, Params, Body}, Imports, AliasMap, LocalFns) ->
    {function, Line, Name, Params,
     [rewrite_expr(E, Imports, AliasMap, LocalFns) || E <- Body]}.

rewrite_expr({call, Line, Fun, Args}, Imports, AliasMap, LocalFns) ->
    RArgs = [rewrite_expr(A, Imports, AliasMap, LocalFns) || A <- Args],
    case {sets:is_element(Fun, LocalFns), Imports} of
        {false, [ImportMod | _]} ->
            %% Not a local function and we have an import — rewrite to dot call
            {dot_call, Line, ImportMod, Fun, RArgs};
        _ ->
            {call, Line, Fun, RArgs}
    end;
rewrite_expr({dot_call, Line, Mod, Fun, Args}, Imports, AliasMap, LocalFns) ->
    RArgs = [rewrite_expr(A, Imports, AliasMap, LocalFns) || A <- Args],
    case maps:get(Mod, AliasMap, undefined) of
        undefined -> {dot_call, Line, Mod, Fun, RArgs};
        FullMod   -> {dot_call, Line, FullMod, Fun, RArgs}
    end;
rewrite_expr({op, Line, Op, Lhs, Rhs}, Imports, AliasMap, LocalFns) ->
    {op, Line, Op,
     rewrite_expr(Lhs, Imports, AliasMap, LocalFns),
     rewrite_expr(Rhs, Imports, AliasMap, LocalFns)};
rewrite_expr({unary, Line, Op, Expr}, Imports, AliasMap, LocalFns) ->
    {unary, Line, Op, rewrite_expr(Expr, Imports, AliasMap, LocalFns)};
rewrite_expr({assign, Line, Var, Expr}, Imports, AliasMap, LocalFns) ->
    {assign, Line, Var, rewrite_expr(Expr, Imports, AliasMap, LocalFns)};
rewrite_expr({if_expr, Line, Cond, Then, Else}, Imports, AliasMap, LocalFns) ->
    {if_expr, Line,
     rewrite_expr(Cond, Imports, AliasMap, LocalFns),
     [rewrite_expr(E, Imports, AliasMap, LocalFns) || E <- Then],
     [rewrite_expr(E, Imports, AliasMap, LocalFns) || E <- Else]};
rewrite_expr({switch_expr, Line, Scrutinee, Clauses}, Imports, AliasMap, LocalFns) ->
    {switch_expr, Line,
     rewrite_expr(Scrutinee, Imports, AliasMap, LocalFns),
     [rewrite_clause(C, Imports, AliasMap, LocalFns) || C <- Clauses]};
rewrite_expr({case_expr, Line, Scrutinee, Clauses}, Imports, AliasMap, LocalFns) ->
    {case_expr, Line,
     rewrite_expr(Scrutinee, Imports, AliasMap, LocalFns),
     [rewrite_clause(C, Imports, AliasMap, LocalFns) || C <- Clauses]};
rewrite_expr({block, Line, Params, Body}, Imports, AliasMap, LocalFns) ->
    {block, Line, Params,
     [rewrite_expr(E, Imports, AliasMap, LocalFns) || E <- Body]};
rewrite_expr({fn_expr, Line, Params, Body}, Imports, AliasMap, LocalFns) ->
    {fn_expr, Line, Params,
     [rewrite_expr(E, Imports, AliasMap, LocalFns) || E <- Body]};
rewrite_expr({try_expr, Line, Body, Rescues}, Imports, AliasMap, LocalFns) ->
    {try_expr, Line,
     [rewrite_expr(E, Imports, AliasMap, LocalFns) || E <- Body],
     [rewrite_clause(C, Imports, AliasMap, LocalFns) || C <- Rescues]};
rewrite_expr({tuple, Line, Elems}, Imports, AliasMap, LocalFns) ->
    {tuple, Line, [rewrite_expr(E, Imports, AliasMap, LocalFns) || E <- Elems]};
rewrite_expr({list, Line, Elems}, Imports, AliasMap, LocalFns) ->
    {list, Line, [rewrite_expr(E, Imports, AliasMap, LocalFns) || E <- Elems]};
rewrite_expr({map_lit, Line, Pairs}, Imports, AliasMap, LocalFns) ->
    {map_lit, Line,
     [{K, rewrite_expr(V, Imports, AliasMap, LocalFns)} || {K, V} <- Pairs]};
rewrite_expr(Other, _Imports, _AliasMap, _LocalFns) ->
    %% Literals, vars, atoms, patterns — pass through unchanged
    Other.

rewrite_clause({case_clause, Line, Pats, Guard, Body}, Imports, AliasMap, LocalFns) ->
    {case_clause, Line, Pats, Guard,
     [rewrite_expr(E, Imports, AliasMap, LocalFns) || E <- Body]}.

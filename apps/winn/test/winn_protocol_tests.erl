%% winn_protocol_tests.erl
%% Tests for protocols (#14).

-module(winn_protocol_tests).
-include_lib("eunit/include/eunit.hrl").

compile_and_load(Source) ->
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── Parser ──────────────────────────────────────────────────────────────────

protocol_parses_test() ->
    Source = "module Proto1\n"
             "  protocol do\n"
             "    def to_s(value)\n"
             "      \"default\"\n"
             "    end\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, [{module, _, 'Proto1', Body}]} = winn_parser:parse(Tokens),
    Protos = [P || {protocol_def, _, _} = P <- Body],
    ?assertEqual(1, length(Protos)).

impl_parses_test() ->
    Source = "module ImplTest\n"
             "  struct [:name]\n"
             "  impl MyProto do\n"
             "    def to_s(v)\n"
             "      v.name\n"
             "    end\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, [{module, _, 'ImplTest', Body}]} = winn_parser:parse(Tokens),
    Impls = [I || {impl_def, _, _, _} = I <- Body],
    ?assertMatch([{impl_def, _, 'MyProto', _}], Impls).

%% ── Protocol dispatch function generation ───────────────────────────────────

protocol_generates_dispatch_test() ->
    Source = "module ShowProto\n"
             "  protocol do\n"
             "    def show(value)\n"
             "      \"default\"\n"
             "    end\n"
             "  end\n"
             "end\n",
    Mod = compile_and_load(Source),
    %% The module should have a show/1 function (dispatch wrapper)
    Exports = Mod:module_info(exports),
    ?assert(lists:member({show, 1}, Exports)).

%% ── Impl generates registration ─────────────────────────────────────────────

impl_generates_register_test() ->
    Source = "module RegTest\n"
             "  struct [:val]\n"
             "  impl ShowProto do\n"
             "    def show(x)\n"
             "      \"RegTest\"\n"
             "    end\n"
             "  end\n"
             "end\n",
    Mod = compile_and_load(Source),
    Exports = Mod:module_info(exports),
    ?assert(lists:member({'__register_impls__', 0}, Exports)).

%% ── End-to-end protocol dispatch ────────────────────────────────────────────

protocol_dispatch_e2e_test() ->
    %% Define protocol
    ProtoSrc = "module Describable\n"
               "  protocol do\n"
               "    def describe(value)\n"
               "      \"unknown\"\n"
               "    end\n"
               "  end\n"
               "end\n",
    ProtoMod = compile_and_load(ProtoSrc),

    %% Define struct + impl
    ImplSrc = "module Animal\n"
              "  struct [:species, :name]\n"
              "  impl Describable do\n"
              "    def describe(animal)\n"
              "      animal.species <> \" named \" <> animal.name\n"
              "    end\n"
              "  end\n"
              "end\n",
    ImplMod = compile_and_load(ImplSrc),

    %% Register implementations
    ImplMod:'__register_impls__'(),

    %% Dispatch
    Animal = ImplMod:new(#{species => <<"Cat">>, name => <<"Whiskers">>}),
    Result = ProtoMod:describe(Animal),
    ?assertEqual(<<"Cat named Whiskers">>, Result).

%% ── Multiple implementations ────────────────────────────────────────────────

multiple_impls_test() ->
    %% Protocol
    PSrc = "module Sizeable\n"
           "  protocol do\n"
           "    def size(value)\n"
           "      0\n"
           "    end\n"
           "  end\n"
           "end\n",
    PMod = compile_and_load(PSrc),

    %% First impl
    Src1 = "module Box\n"
           "  struct [:width, :height]\n"
           "  impl Sizeable do\n"
           "    def size(box)\n"
           "      box.width * box.height\n"
           "    end\n"
           "  end\n"
           "end\n",
    Mod1 = compile_and_load(Src1),
    Mod1:'__register_impls__'(),

    %% Second impl
    Src2 = "module Circle\n"
           "  struct [:radius]\n"
           "  impl Sizeable do\n"
           "    def size(circle)\n"
           "      circle.radius * circle.radius * 3\n"
           "    end\n"
           "  end\n"
           "end\n",
    Mod2 = compile_and_load(Src2),
    Mod2:'__register_impls__'(),

    %% Dispatch to correct implementation
    Box = Mod1:new(#{width => 5, height => 10}),
    Circle = Mod2:new(#{radius => 7}),
    ?assertEqual(50, PMod:size(Box)),
    ?assertEqual(147, PMod:size(Circle)).

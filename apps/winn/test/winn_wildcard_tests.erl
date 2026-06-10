%% winn_wildcard_tests.erl — regression tests for repeated `_` wildcards (#170).
%%
%% Each `_` must compile to a distinct Core Erlang variable; emitting the literal
%% `'_'` for every wildcard made core_lint reject any pattern/head with more than
%% one (`{duplicate_var,'_',...}`).

-module(winn_wildcard_tests).
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

%% Two `_` across one function head (the originally reported repro).
repeated_wildcard_in_head_test() ->
    Src = "module DupWildHead\n"
          "  def head_or([x | _], _)\n"
          "    x\n"
          "  end\n"
          "  def head_or(_list, fallback)\n"
          "    fallback\n"
          "  end\n"
          "end\n",
    Mod = compile_and_load(Src),
    ?assertEqual(1, Mod:head_or([1, 2, 3], 0)),
    ?assertEqual(0, Mod:head_or([], 0)).

%% Two `_` inside a single tuple pattern.
repeated_wildcard_in_tuple_test() ->
    Src = "module DupWildTuple\n"
          "  def third({_, _, c})\n"
          "    c\n"
          "  end\n"
          "end\n",
    Mod = compile_and_load(Src),
    ?assertEqual(3, Mod:third({1, 2, 3})).

%% Wildcards in a switch clause pattern alongside a head wildcard.
repeated_wildcard_in_switch_test() ->
    Src = "module DupWildSwitch\n"
          "  def tag(_ignored, pair)\n"
          "    switch pair\n"
          "      {_, _} => :two\n"
          "      _ => :other\n"
          "    end\n"
          "  end\n"
          "end\n",
    Mod = compile_and_load(Src),
    ?assertEqual(two, Mod:tag(0, {1, 2})),
    ?assertEqual(other, Mod:tag(0, 5)).

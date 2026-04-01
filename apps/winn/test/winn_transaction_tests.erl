%% winn_transaction_tests.erl
%% Tests for database transactions (#42).

-module(winn_transaction_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Repo exports transaction/1 ─────────────────────────────────────────────

repo_exports_transaction_test() ->
    Exports = winn_repo:module_info(exports),
    ?assert(lists:member({transaction, 1}, Exports)).

%% ── Transaction compiles from Winn source ───────────────────────────────────

transaction_compiles_test() ->
    Source = "module TxTest\n"
             "  def run()\n"
             "    Repo.transaction(fn() =>\n"
             "      42\n"
             "    end)\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    %% Module should compile and export run/0
    ?assert(erlang:function_exported(ModName, run, 0)).

%% ── Transaction with multiple operations compiles ───────────────────────────

transaction_multi_op_compiles_test() ->
    Source = "module TxMulti\n"
             "  def run()\n"
             "    Repo.transaction(fn() =>\n"
             "      a = 1\n"
             "      b = 2\n"
             "      a + b\n"
             "    end)\n"
             "  end\n"
             "end\n",
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, _AST} = winn_parser:parse(Tokens),
    %% Parses successfully
    ok.

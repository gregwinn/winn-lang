%% winn_docs_tests.erl
%% Tests for the documentation generator (winn docs, #10).

-module(winn_docs_tests).
-include_lib("eunit/include/eunit.hrl").

%% ── Comment extraction ──────────────────────────────────────────────────────

comment_extraction_test() ->
    Source = "module Greeter\n"
             "  # Greet a user by name.\n"
             "  # Returns a greeting string.\n"
             "  def greet(name)\n"
             "    \"Hello, \" <> name\n"
             "  end\n"
             "end\n",
    {ok, {_, Markdown, _}} = winn_docs:generate_module_doc_from_string(Source),
    %% Should contain the doc comments
    ?assert(binary:match(Markdown, <<"Greet a user by name.">>) =/= nomatch),
    ?assert(binary:match(Markdown, <<"Returns a greeting string.">>) =/= nomatch).

no_comment_test() ->
    Source = "module NoDoc\n"
             "  def run()\n"
             "    42\n"
             "  end\n"
             "end\n",
    {ok, {_, Markdown, _}} = winn_docs:generate_module_doc_from_string(Source),
    ?assert(binary:match(Markdown, <<"## `run()`">>) =/= nomatch).

%% ── Module doc extraction ───────────────────────────────────────────────────

module_doc_test() ->
    Source = "module Calculator\n"
             "  # A simple calculator module.\n"
             "  def add(a, b)\n"
             "    a + b\n"
             "  end\n"
             "end\n",
    {ok, {_, Markdown, _}} = winn_docs:generate_module_doc_from_string(Source),
    ?assert(binary:match(Markdown, <<"# Calculator">>) =/= nomatch),
    ?assert(binary:match(Markdown, <<"simple calculator module">>) =/= nomatch).

%% ── Function signature formatting ───────────────────────────────────────────

function_signature_test() ->
    Source = "module Sig\n"
             "  def process(name, count)\n"
             "    name\n"
             "  end\n"
             "end\n",
    {ok, {_, Markdown, _}} = winn_docs:generate_module_doc_from_string(Source),
    ?assert(binary:match(Markdown, <<"## `process(name, count)`">>) =/= nomatch).

%% ── Dependency extraction ───────────────────────────────────────────────────

deps_extracts_custom_modules_test() ->
    Source = "module Api\n"
             "  def run()\n"
             "    Auth.verify(\"token\")\n"
             "  end\n"
             "end\n",
    {ok, {_, _, Deps}} = winn_docs:generate_module_doc_from_string(Source),
    ?assert(lists:member({'Api', 'Auth'}, Deps)).

deps_skips_stdlib_test() ->
    Source = "module App\n"
             "  def run()\n"
             "    IO.puts(\"hello\")\n"
             "  end\n"
             "end\n",
    {ok, {_, _, Deps}} = winn_docs:generate_module_doc_from_string(Source),
    %% IO is stdlib, should not appear in deps
    ?assertEqual([], Deps).

%% ── Mermaid graph generation ────────────────────────────────────────────────

mermaid_graph_test() ->
    DepEdges = [{'Api', 'Auth'}, {'Api', 'User'}, {'Auth', 'JWT'}],
    Index = winn_docs:generate_index(['Api', 'Auth', 'User'], DepEdges),
    ?assert(binary:match(Index, <<"```mermaid">>) =/= nomatch),
    ?assert(binary:match(Index, <<"graph TD">>) =/= nomatch),
    ?assert(binary:match(Index, <<"Api --> Auth">>) =/= nomatch),
    ?assert(binary:match(Index, <<"Auth --> JWT">>) =/= nomatch).

mermaid_empty_deps_test() ->
    Index = winn_docs:generate_index(['Hello'], []),
    %% No mermaid block when no deps
    ?assertEqual(nomatch, binary:match(Index, <<"mermaid">>)).

%% ── Index module list ───────────────────────────────────────────────────────

index_module_list_test() ->
    Index = winn_docs:generate_index(['Auth', 'User', 'Api'], []),
    %% Should list modules alphabetically with links
    ?assert(binary:match(Index, <<"[Api](api.md)">>) =/= nomatch),
    ?assert(binary:match(Index, <<"[Auth](auth.md)">>) =/= nomatch),
    ?assert(binary:match(Index, <<"[User](user.md)">>) =/= nomatch).

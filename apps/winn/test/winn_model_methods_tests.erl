%% winn_model_methods_tests.erl
%% Tests for Rails-style model query methods (#31).

-module(winn_model_methods_tests).
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

%% ── Schema generates model methods ─────────────────────────────────────────

schema_generates_all_test() ->
    Mod = compile_and_load(
        "module UserMm\n"
        "  use Winn.Schema\n"
        "  schema \"users\" do\n"
        "    field :name, :string\n"
        "  end\n"
        "end\n"),
    Exports = Mod:module_info(exports),
    ?assert(lists:member({all, 0}, Exports)).

schema_generates_find_test() ->
    Mod = compile_and_load(
        "module UserMm2\n"
        "  use Winn.Schema\n"
        "  schema \"users\" do\n"
        "    field :name, :string\n"
        "  end\n"
        "end\n"),
    Exports = Mod:module_info(exports),
    ?assert(lists:member({find, 1}, Exports)).

schema_generates_find_by_test() ->
    Mod = compile_and_load(
        "module UserMm3\n"
        "  use Winn.Schema\n"
        "  schema \"users\" do\n"
        "    field :name, :string\n"
        "  end\n"
        "end\n"),
    Exports = Mod:module_info(exports),
    ?assert(lists:member({find_by, 2}, Exports)).

schema_generates_create_test() ->
    Mod = compile_and_load(
        "module UserMm4\n"
        "  use Winn.Schema\n"
        "  schema \"users\" do\n"
        "    field :name, :string\n"
        "  end\n"
        "end\n"),
    Exports = Mod:module_info(exports),
    ?assert(lists:member({create, 1}, Exports)).

schema_generates_delete_test() ->
    Mod = compile_and_load(
        "module UserMm5\n"
        "  use Winn.Schema\n"
        "  schema \"users\" do\n"
        "    field :name, :string\n"
        "  end\n"
        "end\n"),
    Exports = Mod:module_info(exports),
    ?assert(lists:member({delete, 1}, Exports)).

schema_generates_count_test() ->
    Mod = compile_and_load(
        "module UserMm6\n"
        "  use Winn.Schema\n"
        "  schema \"users\" do\n"
        "    field :name, :string\n"
        "  end\n"
        "end\n"),
    Exports = Mod:module_info(exports),
    ?assert(lists:member({count, 0}, Exports)).

%% ── Model methods work alongside custom functions ───────────────────────────

model_with_custom_functions_test() ->
    Mod = compile_and_load(
        "module UserMm7\n"
        "  use Winn.Schema\n"
        "  schema \"users\" do\n"
        "    field :name, :string\n"
        "    field :age, :integer\n"
        "  end\n"
        "\n"
        "  def greet(user)\n"
        "    \"Hello, \" <> user.name\n"
        "  end\n"
        "end\n"),
    Exports = Mod:module_info(exports),
    %% Both model methods and custom functions exist
    ?assert(lists:member({all, 0}, Exports)),
    ?assert(lists:member({find, 1}, Exports)),
    ?assert(lists:member({create, 1}, Exports)),
    ?assert(lists:member({greet, 1}, Exports)).

%% ── Schema still generates __schema__ functions ─────────────────────────────

schema_still_has_metadata_test() ->
    Mod = compile_and_load(
        "module UserMm8\n"
        "  use Winn.Schema\n"
        "  schema \"users\" do\n"
        "    field :name, :string\n"
        "    field :email, :string\n"
        "  end\n"
        "end\n"),
    ?assertEqual(<<"users">>, Mod:'__schema__'(source)),
    ?assertEqual([name, email], Mod:'__schema__'(fields)).

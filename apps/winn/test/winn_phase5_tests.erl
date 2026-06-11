-module(winn_phase5_tests).
-include_lib("eunit/include/eunit.hrl").

lex(Src)       -> {ok, RawTok_, _} = winn_lexer:string(Src), Tokens = winn_newline_filter:filter(RawTok_), Tokens.
parse(Src)     -> {ok, Forms} = winn_parser:parse(lex(Src)), Forms.
transform(Src) -> winn_transform:transform(parse(Src)).
load_src(Src) ->
    Forms = transform(Src),
    [CoreMod | _] = winn_codegen:gen(Forms),
    {ok, ModName, Bin} = winn_core_emit:emit_to_binary(CoreMod),
    {module, ModName} = code:load_binary(ModName, "nofile", Bin),
    ModName.

%% ── Parser tests ─────────────────────────────────────────────────────────

parse_schema_def_test() ->
    Src = "module Post\n"
          "  use Winn.Schema\n"
          "  schema \"posts\" do\n"
          "    field :title, :string\n"
          "    field :body, :text\n"
          "  end\n"
          "end",
    [{module,_,'Post', Body}] = parse(Src),
    SchemaDefs = [X || {schema_def,_,_,_} = X <- Body],
    ?assertMatch([{schema_def, _, <<"posts">>, _}], SchemaDefs),
    [{schema_def, _, _, Fields}] = SchemaDefs,
    ?assertMatch([{field,_,title,string},{field,_,body,text}], Fields).

parse_schema_empty_test() ->
    Src = "module Empty use Winn.Schema schema \"empty\" do end end",
    [{module,_,'Empty', Body}] = parse(Src),
    SchemaDefs = [X || {schema_def,_,_,_} = X <- Body],
    ?assertMatch([{schema_def, _, <<"empty">>, []}], SchemaDefs).

%% ── Transform tests ──────────────────────────────────────────────────────

transform_schema_generates_schema_fn_test() ->
    Src = "module Post2\n"
          "  use Winn.Schema\n"
          "  schema \"posts\" do\n"
          "    field :title, :string\n"
          "  end\n"
          "end",
    [{module,_,'Post2', Body}] = transform(Src),
    SchemaFns = [F || {function,_,'__schema__',_,_} = F <- Body],
    ?assert(length(SchemaFns) >= 1).

transform_schema_generates_new_fn_test() ->
    Src = "module Post3\n"
          "  use Winn.Schema\n"
          "  schema \"posts\" do\n"
          "    field :title, :string\n"
          "    field :body, :text\n"
          "  end\n"
          "end",
    [{module,_,'Post3', Body}] = transform(Src),
    NewFns = [F || {function,_,new,_,_} = F <- Body],
    ?assertMatch([_], NewFns).

%% ── End-to-end compiled schema tests ─────────────────────────────────────

schema_source_test() ->
    Src = "module Article\n"
          "  use Winn.Schema\n"
          "  schema \"articles\" do\n"
          "    field :title, :string\n"
          "    field :body, :text\n"
          "    field :published, :boolean\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    ?assertEqual(<<"articles">>, ModName:'__schema__'(source)).

schema_fields_test() ->
    Src = "module Tag\n"
          "  use Winn.Schema\n"
          "  schema \"tags\" do\n"
          "    field :name, :string\n"
          "    field :color, :string\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    Fields = ModName:'__schema__'(fields),
    ?assertEqual([name, color], Fields).

schema_new_test() ->
    Src = "module Comment\n"
          "  use Winn.Schema\n"
          "  schema \"comments\" do\n"
          "    field :body, :string\n"
          "    field :author, :string\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    Struct = ModName:new(#{body => <<"Hello">>, author => <<"Alice">>}),
    ?assertEqual(<<"Hello">>, maps:get(body, Struct)),
    ?assertEqual(<<"Alice">>, maps:get(author, Struct)).

schema_new_defaults_nil_test() ->
    Src = "module Widget\n"
          "  use Winn.Schema\n"
          "  schema \"widgets\" do\n"
          "    field :name, :string\n"
          "    field :color, :string\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    Struct = ModName:new(#{}),
    ?assertEqual(nil, maps:get(name, Struct)),
    ?assertEqual(nil, maps:get(color, Struct)).

%% ── Changeset tests ───────────────────────────────────────────────────────

changeset_valid_test() ->
    Data = #{title => nil, body => nil},
    CS   = winn_changeset:new(Data, #{title => <<"Hello">>, body => <<"World">>}),
    CS2  = winn_changeset:validate_required(CS, [title, body]),
    ?assert(winn_changeset:valid(CS2)).

changeset_invalid_missing_test() ->
    Data = #{title => nil, body => nil},
    CS   = winn_changeset:new(Data, #{body => <<"World">>}),
    CS2  = winn_changeset:validate_required(CS, [title, body]),
    ?assertNot(winn_changeset:valid(CS2)),
    Errors = winn_changeset:errors(CS2),
    ?assert(lists:keymember(title, 1, Errors)).

changeset_apply_test() ->
    Data = #{title => <<"Old">>, body => nil},
    CS   = winn_changeset:new(Data, #{title => <<"New">>}),
    Applied = winn_changeset:apply_changes(CS),
    ?assertEqual(<<"New">>, maps:get(title, Applied)).

changeset_validate_length_test() ->
    Data = #{title => nil},
    CS   = winn_changeset:new(Data, #{title => <<"Hi">>}),
    CS2  = winn_changeset:validate_length(CS, title, min, 5),
    ?assertNot(winn_changeset:valid(CS2)).

%% ── SQL generation tests (no DB needed) ──────────────────────────────────

sql_insert_test() ->
    Src = "module SqlPost\n"
          "  use Winn.Schema\n"
          "  schema \"posts\" do\n"
          "    field :title, :string\n"
          "    field :body, :text\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    {SQL, _Vals} = winn_repo:sql_for_insert(ModName, #{title => <<"T">>, body => <<"B">>}),
    ?assert(binary:match(SQL, <<"INSERT INTO posts">>) =/= nomatch).

sql_select_test() ->
    Src = "module SqlTag\n"
          "  use Winn.Schema\n"
          "  schema \"tags\" do\n"
          "    field :name, :string\n"
          "  end\n"
          "end",
    ModName = load_src(Src),
    {SQL, []} = winn_repo:sql_for_select(ModName, #{}),
    ?assert(binary:match(SQL, <<"SELECT * FROM tags">>) =/= nomatch).

%% Regression for #172: row mapping must use the result-set column metadata so
%% the DB-managed `id` (returned first by RETURNING * / SELECT *) is included and
%% values aren't shifted onto the wrong keys. insert/get/update previously used
%% the schema field list (which omits `id`), corrupting every record.
%% Cols mimic the epgsql #column shape — only element(2) (the name) is read.
row_to_map_cols_includes_id_test() ->
    Cols = [{column, <<"id">>}, {column, <<"email">>}, {column, <<"password_hash">>}],
    Row  = {1, <<"a@b.com">>, <<"$pbkdf2-sha256$...">>},
    ?assertEqual(#{id => 1,
                   email => <<"a@b.com">>,
                   password_hash => <<"$pbkdf2-sha256$...">>},
                 winn_repo:row_to_map_cols(Cols, Row)).

%% ── Regression ───────────────────────────────────────────────────────────

hello_regression_test() ->
    Src = "module Hello5\n"
          "  def main()\n"
          "    IO.puts(\"Hello from Phase 5!\")\n"
          "  end\n"
          "end",
    Forms = transform(Src),
    [CoreMod | _] = winn_codegen:gen(Forms),
    {ok, _, Bin} = winn_core_emit:emit_to_binary(CoreMod),
    ?assert(is_binary(Bin)).

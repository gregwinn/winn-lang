%% winn_generator.erl
%% Code generators for models, migrations, tasks, routers, and scaffolds.

-module(winn_generator).
-export([generate/2, parse_fields/1]).

%% ── Public API ───────────────────────────────────────────────────────────────

generate(model, [Name | FieldArgs]) ->
    Fields = parse_fields(FieldArgs),
    ModName = to_pascal(Name),
    TableName = to_snake(Name) ++ "s",
    Content = model_template(ModName, TableName, Fields),
    Path = "src/" ++ to_snake(Name) ++ ".winn",
    write_file(Path, Content);

generate(migration, [Name | FieldArgs]) ->
    Fields = parse_fields(FieldArgs),
    Timestamp = timestamp(),
    FileName = Timestamp ++ "_" ++ to_snake(Name),
    Content = migration_template(to_pascal(Name), Fields),
    Path = "migrations/" ++ FileName ++ ".winn",
    ok = filelib:ensure_path("migrations"),
    write_file(Path, Content);

generate(task, [Name]) ->
    Parts = string:split(Name, ":", all),
    ModParts = [to_pascal(P) || P <- Parts],
    ModName = "Tasks." ++ lists:flatten(lists:join(".", ModParts)),
    FileName = lists:flatten(lists:join("_", Parts)),
    Content = task_template(ModName),
    Path = "tasks/" ++ FileName ++ ".winn",
    ok = filelib:ensure_path("tasks"),
    write_file(Path, Content);

generate(router, [Name]) ->
    ModName = to_pascal(Name),
    Content = router_template(ModName),
    Path = "src/" ++ to_snake(Name) ++ ".winn",
    write_file(Path, Content);

generate(scaffold, [Name | FieldArgs]) ->
    Fields = parse_fields(FieldArgs),
    %% Generate model
    generate(model, [Name | FieldArgs]),
    %% Generate router
    ModName = to_pascal(Name),
    RouterContent = scaffold_router_template(ModName, to_snake(Name)),
    RouterPath = "src/" ++ to_snake(Name) ++ "_router.winn",
    write_file(RouterPath, RouterContent),
    %% Generate test
    TestContent = scaffold_test_template(ModName),
    TestPath = "test/" ++ to_snake(Name) ++ "_test.winn",
    ok = filelib:ensure_path("test"),
    write_file(TestPath, TestContent);

generate(_, _) ->
    io:format("Unknown generator. Available: model, migration, task, router, scaffold~n"),
    {error, unknown_generator}.

%% ── Field parsing ────────────────────────────────────────────────────────────

parse_fields(Args) ->
    lists:filtermap(fun(Arg) ->
        case string:split(Arg, ":") of
            [Name, Type] -> {true, {Name, Type}};
            _ -> false
        end
    end, Args).

%% ── Templates ────────────────────────────────────────────────────────────────

model_template(ModName, TableName, Fields) ->
    FieldAtoms = [":\"" ++ N ++ "\"" || {N, _} <- Fields],
    StructFields = string:join(FieldAtoms, ", "),
    SchemaFields = [io_lib:format("    field :~s, :~s~n", [N, T]) || {N, T} <- Fields],
    lists:flatten(io_lib:format(
        "module ~s~n"
        "  use Winn.Schema~n"
        "~n"
        "  struct [~s]~n"
        "~n"
        "  schema \"~s\" do~n"
        "~s"
        "  end~n"
        "end~n",
        [ModName, StructFields, TableName, SchemaFields])).

migration_template(Name, Fields) ->
    case Fields of
        [] ->
            lists:flatten(io_lib:format(
                "module Migrations.~s~n"
                "  def up()~n"
                "    Repo.execute(\"-- Add your SQL here\")~n"
                "  end~n"
                "~n"
                "  def down()~n"
                "    Repo.execute(\"-- Reverse the migration\")~n"
                "  end~n"
                "end~n",
                [Name]));
        _ ->
            TableName = guess_table_from_migration(Name),
            Columns = [io_lib:format("      ~s ~s", [N, sql_type(T)]) || {N, T} <- Fields],
            ColumnStr = string:join(Columns, ",\n"),
            lists:flatten(io_lib:format(
                "module Migrations.~s~n"
                "  def up()~n"
                "    Repo.execute(\"CREATE TABLE ~s (~n"
                "      id SERIAL PRIMARY KEY,~n"
                "~s,~n"
                "      created_at TIMESTAMP DEFAULT NOW()~n"
                "    )\")~n"
                "  end~n"
                "~n"
                "  def down()~n"
                "    Repo.execute(\"DROP TABLE ~s\")~n"
                "  end~n"
                "end~n",
                [Name, TableName, ColumnStr, TableName]))
    end.

task_template(ModName) ->
    lists:flatten(io_lib:format(
        "module ~s~n"
        "  use Winn.Task~n"
        "~n"
        "  def run(args)~n"
        "    IO.puts(\"Running task...\")~n"
        "  end~n"
        "end~n",
        [ModName])).

router_template(ModName) ->
    lists:flatten(io_lib:format(
        "module ~s~n"
        "  use Winn.Router~n"
        "~n"
        "  def routes()~n"
        "    [~n"
        "      {:get, \"/\", :index}~n"
        "    ]~n"
        "  end~n"
        "~n"
        "  def index(conn)~n"
        "    Server.json(conn, %{status: \"ok\"})~n"
        "  end~n"
        "end~n",
        [ModName])).

scaffold_router_template(ModName, SnakeName) ->
    lists:flatten(io_lib:format(
        "module ~sRouter~n"
        "  use Winn.Router~n"
        "~n"
        "  def routes()~n"
        "    [~n"
        "      {:get, \"/~ss\", :index},~n"
        "      {:get, \"/~ss/:id\", :show},~n"
        "      {:post, \"/~ss\", :create}~n"
        "    ]~n"
        "  end~n"
        "~n"
        "  def index(conn)~n"
        "    {:ok, items} = ~s.all()~n"
        "    Server.json(conn, items)~n"
        "  end~n"
        "~n"
        "  def show(conn)~n"
        "    id = Server.path_param(conn, \"id\")~n"
        "    {:ok, item} = ~s.find(id)~n"
        "    Server.json(conn, item)~n"
        "  end~n"
        "~n"
        "  def create(conn)~n"
        "    params = Server.body_params(conn)~n"
        "    {:ok, item} = ~s.create(params)~n"
        "    Server.json(conn, item, 201)~n"
        "  end~n"
        "end~n",
        [ModName, SnakeName, SnakeName, SnakeName,
         ModName, ModName, ModName])).

scaffold_test_template(ModName) ->
    lists:flatten(io_lib:format(
        "module ~sTest~n"
        "  use Winn.Test~n"
        "~n"
        "  def test_create()~n"
        "    assert(true)~n"
        "  end~n"
        "~n"
        "  def test_find()~n"
        "    assert(true)~n"
        "  end~n"
        "end~n",
        [ModName])).

%% ── Helpers ──────────────────────────────────────────────────────────────────

to_pascal(Name) ->
    Parts = string:split(Name, "_", all),
    lists:flatten([capitalize(P) || P <- Parts]).

capitalize([]) -> [];
capitalize([C | Rest]) when C >= $a, C =< $z -> [C - 32 | Rest];
capitalize(S) -> S.

to_snake(Name) ->
    string:lowercase(Name).

timestamp() ->
    {{Y, M, D}, {H, Mi, S}} = calendar:universal_time(),
    lists:flatten(io_lib:format("~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B",
                                [Y, M, D, H, Mi, S])).

guess_table_from_migration(Name) ->
    %% "CreateUsers" -> "users", "AddEmailToUsers" -> "users"
    Lower = string:lowercase(Name),
    case re:run(Lower, "(?:create|add.*to)_?(\\w+)$", [{capture, [1], list}]) of
        {match, [Table]} -> Table;
        nomatch -> Lower ++ "s"
    end.

sql_type("string")   -> "VARCHAR(255)";
sql_type("text")     -> "TEXT";
sql_type("integer")  -> "INTEGER";
sql_type("float")    -> "FLOAT";
sql_type("boolean")  -> "BOOLEAN";
sql_type("datetime") -> "TIMESTAMP";
sql_type(Other)      -> string:uppercase(Other).

write_file(Path, Content) ->
    case filelib:is_file(Path) of
        true ->
            io:format("  exists  ~s~n", [Path]),
            {error, already_exists};
        false ->
            ok = file:write_file(Path, Content),
            io:format("  create  ~s~n", [Path]),
            ok
    end.

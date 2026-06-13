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
    ok = filelib:ensure_path("src/models"),
    Path = "src/models/" ++ to_snake(Name) ++ ".winn",
    write_file(Path, Content);

generate(migration, [Name | FieldArgs]) ->
    Fields = parse_fields(FieldArgs),
    Timestamp = timestamp(),
    FileName = Timestamp ++ "_" ++ to_snake(Name),
    Content = migration_template(to_pascal(Name), Fields),
    Path = "db/migrations/" ++ FileName ++ ".winn",
    ok = filelib:ensure_path("db/migrations"),
    write_file(Path, Content);

generate(task, [Name]) ->
    Parts = string:split(Name, ":", all),
    ModParts = [to_pascal(P) || P <- Parts],
    ModName = "Tasks." ++ lists:flatten(lists:join(".", ModParts)),
    FileName = lists:flatten(lists:join("_", Parts)),
    Content = task_template(ModName),
    Path = "src/tasks/" ++ FileName ++ ".winn",
    ok = filelib:ensure_path("src/tasks"),
    write_file(Path, Content);

generate(router, [Name]) ->
    ModName = to_pascal(Name) ++ "Controller",
    Content = router_template(ModName),
    ok = filelib:ensure_path("src/controllers"),
    Path = "src/controllers/" ++ to_snake(Name) ++ "_controller.winn",
    write_file(Path, Content);

generate(scaffold, [Name | FieldArgs]) ->
    _Fields = parse_fields(FieldArgs),
    %% Generate model
    generate(model, [Name | FieldArgs]),
    %% Generate controller
    ModName = to_pascal(Name),
    RouterContent = scaffold_router_template(ModName, to_snake(Name)),
    ok = filelib:ensure_path("src/controllers"),
    RouterPath = "src/controllers/" ++ to_snake(Name) ++ "_controller.winn",
    write_file(RouterPath, RouterContent),
    %% Generate test
    TestContent = scaffold_test_template(ModName),
    TestPath = "test/" ++ to_snake(Name) ++ "_test.winn",
    ok = filelib:ensure_path("test"),
    write_file(TestPath, TestContent);

generate(auth, _Args) ->
    ok = filelib:ensure_path("src/models"),
    ok = filelib:ensure_path("src/controllers"),
    ok = filelib:ensure_path("db/migrations"),
    Ts = timestamp(),
    %% Models (schema-only; the schema block provides __schema__ for Repo).
    write_file("src/models/user.winn",
               auth_model_template("User", "users",
                   [{"email", "string"}, {"password_hash", "string"},
                    {"verified", "boolean"}, {"created_at", "integer"}])),
    write_file("src/models/auth_token.winn",
               auth_model_template("AuthToken", "auth_tokens",
                   [{"user_id", "integer"}, {"token_hash", "string"},
                    {"purpose", "string"}, {"expires_at", "integer"},
                    {"created_at", "integer"}])),
    %% Migrations (custom, for proper constraints). The `01`/`02` suffix orders
    %% users before auth_tokens (which references it).
    write_file("db/migrations/" ++ Ts ++ "01_create_users.winn", auth_users_migration()),
    write_file("db/migrations/" ++ Ts ++ "02_create_auth_tokens.winn", auth_tokens_migration()),
    %% Router with the full auth endpoint set.
    write_file("src/controllers/auth_controller.winn", auth_controller_template()),
    io:format(
        "~nAuth scaffolded. Next steps:~n"
        "  1. Set a signing secret at startup, e.g. in main():~n"
        "       Config.put(:auth, :secret, System.get_env(\"JWT_SECRET\"))~n"
        "  2. Mount AuthController and run migrations: winn migrate~n"
        "  3. See docs/auth.md for the full guide (refresh, cookie mode, recovery).~n~n"),
    ok;

generate(_, _) ->
    io:format("Unknown generator. Available: model, migration, task, router, scaffold, auth~n"),
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

auth_model_template(ModName, Table, Fields) ->
    SchemaFields = [io_lib:format("    field :~s, :~s~n", [N, T]) || {N, T} <- Fields],
    lists:flatten(io_lib:format(
        "module ~s~n"
        "  use Winn.Schema~n"
        "~n"
        "  schema \"~s\" do~n"
        "~s"
        "  end~n"
        "end~n",
        [ModName, Table, SchemaFields])).

auth_users_migration() ->
    "module Migrations.CreateUsers\n"
    "  def up()\n"
    "    Repo.execute(\"CREATE TABLE users (\n"
    "      id SERIAL PRIMARY KEY,\n"
    "      email VARCHAR(255) NOT NULL UNIQUE,\n"
    "      password_hash TEXT NOT NULL,\n"
    "      verified BOOLEAN DEFAULT FALSE,\n"
    "      created_at BIGINT\n"
    "    )\")\n"
    "  end\n"
    "\n"
    "  def down()\n"
    "    Repo.execute(\"DROP TABLE users\")\n"
    "  end\n"
    "end\n".

auth_tokens_migration() ->
    "module Migrations.CreateAuthTokens\n"
    "  def up()\n"
    "    Repo.execute(\"CREATE TABLE auth_tokens (\n"
    "      id SERIAL PRIMARY KEY,\n"
    "      user_id INTEGER NOT NULL,\n"
    "      token_hash TEXT NOT NULL UNIQUE,\n"
    "      purpose TEXT NOT NULL,\n"
    "      expires_at BIGINT NOT NULL,\n"
    "      created_at BIGINT\n"
    "    )\")\n"
    "  end\n"
    "\n"
    "  def down()\n"
    "    Repo.execute(\"DROP TABLE auth_tokens\")\n"
    "  end\n"
    "end\n".

%% Full email/password auth router (Bearer strategy). Note: `ok`/`err` are reserved
%% and can't be map keys, so success bodies use `%{status: "ok"}`.
auth_controller_template() ->
    "module AuthController\n"
    "  use Winn.Router\n"
    "\n"
    "  def routes()\n"
    "    [\n"
    "      {:post, \"/auth/register\", :register},\n"
    "      {:post, \"/auth/login\",    :login},\n"
    "      {:post, \"/auth/refresh\",  :refresh},\n"
    "      {:post, \"/auth/logout\",   :logout},\n"
    "      {:get,  \"/auth/verify\",   :verify},\n"
    "      {:post, \"/auth/forgot\",   :forgot},\n"
    "      {:post, \"/auth/reset\",    :reset},\n"
    "      {:get,  \"/api/me\",        :me}\n"
    "    ]\n"
    "  end\n"
    "\n"
    "  def middleware()\n"
    "    [:cors, :auth]\n"
    "  end\n"
    "\n"
    "  def auth_config()\n"
    "    %{\n"
    "      secret: Config.get(:auth, :secret),\n"
    "      exclude: [\"/auth/login\", \"/auth/register\", \"/auth/refresh\",\n"
    "                \"/auth/verify\", \"/auth/forgot\", \"/auth/reset\"]\n"
    "    }\n"
    "  end\n"
    "\n"
    "  def register(conn)\n"
    "    params = Server.body_params(conn)\n"
    "    match Auth.register(params.email, params.password)\n"
    "      ok user => Server.json(conn, user, 201)\n"
    "      err reason => Server.json(conn, %{error: reason}, 422)\n"
    "    end\n"
    "  end\n"
    "\n"
    "  def login(conn)\n"
    "    params = Server.body_params(conn)\n"
    "    match Auth.login(params.email, params.password)\n"
    "      ok result => Server.json(conn, result)\n"
    "      err _ => Server.json(conn, %{error: \"invalid login\"}, 401)\n"
    "    end\n"
    "  end\n"
    "\n"
    "  def refresh(conn)\n"
    "    params = Server.body_params(conn)\n"
    "    match Auth.refresh(params.refresh_token)\n"
    "      ok tokens => Server.json(conn, tokens)\n"
    "      err _ => Server.json(conn, %{error: \"invalid refresh token\"}, 401)\n"
    "    end\n"
    "  end\n"
    "\n"
    "  def logout(conn)\n"
    "    params = Server.body_params(conn)\n"
    "    Auth.logout(params.refresh_token)\n"
    "    Server.json(conn, %{status: \"ok\"})\n"
    "  end\n"
    "\n"
    "  def verify(conn)\n"
    "    match Auth.verify_email(Server.query_param(conn, \"token\"))\n"
    "      ok _ => Server.json(conn, %{verified: true})\n"
    "      err _ => Server.json(conn, %{error: \"invalid or expired token\"}, 400)\n"
    "    end\n"
    "  end\n"
    "\n"
    "  def forgot(conn)\n"
    "    params = Server.body_params(conn)\n"
    "    Auth.request_password_reset(params.email)\n"
    "    Server.json(conn, %{status: \"ok\"})\n"
    "  end\n"
    "\n"
    "  def reset(conn)\n"
    "    params = Server.body_params(conn)\n"
    "    match Auth.reset_password(params.token, params.password)\n"
    "      ok _ => Server.json(conn, %{status: \"ok\"})\n"
    "      err _ => Server.json(conn, %{error: \"invalid or expired token\"}, 400)\n"
    "    end\n"
    "  end\n"
    "\n"
    "  def me(conn)\n"
    "    match Auth.current_user(conn)\n"
    "      ok user => Server.json(conn, user)\n"
    "      err _ => Server.json(conn, %{error: \"unauthorized\"}, 401)\n"
    "    end\n"
    "  end\n"
    "end\n".

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
        "module ~sController~n"
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

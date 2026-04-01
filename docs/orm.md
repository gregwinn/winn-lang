# Winn ORM

Winn includes a built-in ORM for PostgreSQL backed by [epgsql](https://github.com/epgsql/epgsql).

## Configuration

Configure the database connection from Winn using `Repo.configure`:

```winn
module MyApp
  def main()
    Repo.configure(%{
      host: "localhost",
      port: 5432,
      database: "my_app_dev",
      username: "postgres",
      password: "secret",
      pool_size: 10
    })

    # Connection pool starts automatically when pool_size is set
    # All Repo operations checkout/checkin connections from the pool
  end
end
```

Call `Repo.configure` early in your app (e.g., in `main()`) before any database operations. Configuration is stored in the Config ETS table and persists for the lifetime of the VM.

### Connection Pool

When `pool_size` is set, a GenServer-based connection pool starts automatically. Connections are reused across queries instead of opening a new one per operation.

```winn
Repo.configure(%{pool_size: 10})   # pool starts with 10 connections

# Check pool status
Repo.pool_status()  # => {:ok, %{idle: 8, busy: 2, max: 10}}
```

Without `pool_size`, Repo falls back to opening/closing a connection per query (backward compatible).

You can also configure individual keys:

```winn
Repo.configure(%{database: "my_app_test"})
```

### Raw SQL

Execute raw SQL queries with `Repo.execute`:

```winn
Repo.execute("CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT)")
Repo.execute("SELECT * FROM users WHERE age > $1", [18])
```

---

## Schemas

Schemas define the structure of your data and map to database tables.

```winn
module Post
  use Winn.Schema

  schema "posts" do
    field :title,     :string
    field :body,      :text
    field :published, :boolean
    field :author_id, :integer
  end
end
```

### `use Winn.Schema` generates:

| Function | Returns |
|----------|---------|
| `Post.__schema__(source)` | `"posts"` — the table name |
| `Post.__schema__(fields)` | `[:title, :body, :published, :author_id]` |
| `Post.__schema__(types)` | `%{title: :string, body: :text, ...}` |
| `Post.new(attrs)` | A map with all fields, defaulting to `nil` |

### Creating structs

```winn
post = Post.new(%{title: "Hello", body: "World"})
# => %{title: "Hello", body: "World", published: nil, author_id: nil}
```

---

## Changesets

Changesets validate and track changes to data before persisting.

```winn
data    = Post.new(%{})
changes = %{title: "My Post", body: "Content here"}

changeset = Changeset.new(data, changes)
changeset = Changeset.validate_required(changeset, [:title, :body])
changeset = Changeset.validate_length(changeset, :title, :min, 3)

match Changeset.valid(changeset)
  ok _ => Repo.insert(post, changes)
  err _ =>
    errors = Changeset.errors(changeset)
    IO.inspect(errors)
end
```

### Changeset Functions

#### `Changeset.new(data, attrs)`
Create a new changeset tracking changes from `data` to `attrs`.

#### `Changeset.validate_required(changeset, fields)`
Ensure fields are present and non-empty in `attrs`.

#### `Changeset.validate_length(changeset, field, :min, n)`
Ensure a string field has at least `n` characters.

#### `Changeset.valid(changeset)`
Returns `true` if there are no errors.

#### `Changeset.errors(changeset)`
Returns a list of `{field, message}` tuples.

#### `Changeset.apply_changes(changeset)`
Merge changes into data and return the result map.

---

## Repo

The Repo module executes database operations.

### Insert

```winn
{:ok, post} = Repo.insert(Post, %{title: "Hello", body: "World"})
```

Inserts a new row. Returns `{:ok, map}` with the persisted record (including `id` from `RETURNING *`).

### Get by ID

```winn
{:ok, post} = Repo.get(Post, 1)
# => {:ok, %{id: 1, title: "Hello", ...}}

{:error, :not_found} = Repo.get(Post, 9999)
```

### Get by field

```winn
{:ok, post} = Repo.get(Post, :title, "Hello")
```

### Get all

```winn
{:ok, posts} = Repo.all(Post)

# With filters
{:ok, posts} = Repo.all(Post, %{published: true})
```

### Update

```winn
{:ok, updated} = Repo.update(post)
```

`post` must be a map with an `id` key and a `__schema__` key pointing to the schema module.

### Delete

```winn
:ok = Repo.delete(post)
```

### SQL Helpers (no DB connection needed)

These are useful for testing or debugging:

```winn
{sql, vals} = Repo.sql_for_insert(Post, %{title: "Hi"})
# sql => "INSERT INTO posts (title, body, ...) VALUES ($1, $2, ...) RETURNING *"

{sql, []} = Repo.sql_for_select(Post, %{})
# sql => "SELECT * FROM posts"
```

---

## Full Example

```winn
module Blog
  def create_post(params)
    data      = Post.new(%{})
    changeset = Changeset.new(data, params)
    changeset = Changeset.validate_required(changeset, [:title, :body])

    match Changeset.valid(changeset)
      ok _ =>
        Repo.insert(Post, Changeset.apply_changes(changeset))
      err _ =>
        {:error, Changeset.errors(changeset)}
    end
  end

  def list_posts()
    Repo.all(Post)
  end

  def get_post(id)
    Repo.get(Post, id)
  end
end
```

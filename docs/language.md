# Winn Language Guide

## Overview

Winn is a dynamically typed, functional language that compiles to the BEAM (Erlang VM). Syntax is inspired by Ruby and Elixir.

## Modules

Every Winn file contains one or more modules. A module is the top-level unit of code organization.

```winn
module Greeter
  def greet(name)
    IO.puts("Hello, " <> name <> "!")
  end
end
```

Module names are capitalized. They compile to lowercase Erlang module atoms (`Greeter` → `:greeter`).

### Dotted Module Names

Modules can use dotted names for hierarchical organization:

```winn
module MyApp.Router
  def routes()
    [{:get, "/", :index}]
  end
end
```

Dotted names compile to dotted atoms (`MyApp.Router` → `:'myapp.router'`).

### Module References as Values

Module names can be passed as values to functions. They compile to lowercase atoms matching the compiled module name:

```winn
Repo.insert(Post, changeset)    # Post becomes the atom :post
Repo.all(Contact)               # Contact becomes :contact
```

### Import

`import` brings a module's functions into scope as local calls:

```winn
module MyApp
  import Enum

  def run()
    map([1,2,3]) do |x| x * 2 end    # instead of Enum.map(...)
  end
end
```

Local functions take priority — if you define a function with the same name as an imported one, your local version is called.

### Alias

`alias` lets you use a short name for a dotted module path:

```winn
module MyApp
  alias MyApp.Auth

  def run()
    Auth.verify("token")    # instead of MyApp.Auth.verify(...)
  end
end
```

The short name is the last segment: `alias MyApp.Auth` makes `Auth` available.

## Functions

Functions are defined with `def` and closed with `end`. The last expression in a function body is the return value.

Function names can end with `?` for predicates:

```winn
def valid?(changeset)
  Changeset.valid(changeset)
end

# Standard library predicates:
List.contains?(2, [1, 2, 3])    # => true
Map.has_key?(user, :name)       # => true
Enum.any?([1, 2, 3]) do |x| x > 2 end  # => true
```

```winn
module Math
  def add(a, b)
    a + b
  end

  def square(n)
    n * n
  end
end
```

### Default Parameter Values

Parameters can have default values. When called with fewer arguments, defaults are filled in:

```winn
def greet(name, greeting = "Hello")
  "#{greeting}, #{name}!"
end

greet("Alice")          # => "Hello, Alice!"
greet("Alice", "Hi")    # => "Hi, Alice!"
```

Multiple defaults are supported — they must come after required parameters:

```winn
def connect(host, port = 5432, timeout = 5000)
  # ...
end

connect("localhost")             # port=5432, timeout=5000
connect("localhost", 3306)       # timeout=5000
connect("localhost", 3306, 10000)
```

Defaults can be strings, integers, floats, atoms, and booleans.

### Multi-clause Functions

Define multiple clauses for pattern-based dispatch:

```winn
module Greeter
  def greet(:world)
    "Hello, World!"
  end

  def greet(name)
    "Hello, " <> name <> "!"
  end
end
```

Clauses are matched top-to-bottom.

## Types and Literals

### Integers and Floats

```winn
42
3.14
-100
```

### Strings

Strings are UTF-8 binaries. Concatenate with `<>` or use interpolation:

```winn
"Hello, " <> "World!"
"Hello, #{name}!"
```

#### String Interpolation

Embed any expression inside `#{}` within a double-quoted string:

```winn
name = "Alice"
IO.puts("Hello, #{name}!")

count = 42
IO.puts("There are #{to_string(count)} items")

IO.puts("#{to_string(1 + 2)} is three")
```

Escape `#` with a backslash to prevent interpolation: `"\#{not interpolated}"`

### Atoms

Atoms are prefixed with `:`:

```winn
:ok
:error
:hello
```

### Booleans

```winn
true
false
```

### Nil

```winn
nil
```

### Lists

```winn
[1, 2, 3]
["alice", "bob", "carol"]
[]
```

### Tuples

```winn
{:ok, value}
{:error, "not found"}
{:user, "Alice", 30}
```

### Maps

```winn
%{name: "Alice", age: 30}
%{status: :active}
```

## Operators

### Arithmetic

```winn
a + b
a - b
a * b
a / b
```

### String Concatenation

```winn
"Hello, " <> name
```

### Comparison

```winn
a == b
a != b
a < b
a > b
a <= b
a >= b
```

### Boolean

```winn
a and b
a or b
not a
```

## Variables

Variables are bound with `=`. They are immutable bindings (like Elixir):

```winn
x = 42
name = "Alice"
result = x + 10
```

### Pattern Assignment

Destructure tuples on the left side of `=`:

```winn
{:ok, value} = {:ok, 42}
# value is now 42

{:ok, {a, b}} = {:ok, {1, 2}}
# a is 1, b is 2
```

If the pattern doesn't match, it raises a runtime error.

## Pipe Operator

The `|>` operator passes the result of the left expression as the first argument to the right:

```winn
"hello world"
  |> String.upcase()
  |> IO.puts()
```

Is equivalent to:

```winn
IO.puts(String.upcase("hello world"))
```

Pipes chain naturally:

```winn
def process(list)
  list
    |> Enum.filter() do |x| x > 0 end
    |> Enum.map()    do |x| x * 2 end
end
```

## Pattern Matching

### Function Clause Patterns

Match on tuples, atoms, integers, and lists in function parameters:

```winn
module Result
  def unwrap({:ok, value})
    value
  end

  def unwrap({:error, reason})
    IO.puts("Error: " <> reason)
    :error
  end
end
```

```winn
module Shape
  def area({:circle, r})
    3.14159 * r * r
  end

  def area({:rect, w, h})
    w * h
  end
end
```

### Wildcard Pattern

Use `_` to ignore a value:

```winn
def handle_info(_, state)
  {:noreply, state}
end
```

### Match Blocks

`match...end` desugars to a case expression. Use after a pipe or with an explicit scrutinee:

```winn
%% Pipe into match
result
  |> match
    ok value => value
    err msg  => IO.puts("Error: " <> msg)
  end

%% Standalone match with scrutinee
match response
  ok data  => IO.puts("Got: " <> data)
  err code => IO.puts("Failed")
end
```

`ok val` matches `{:ok, val}`. `err e` matches `{:error, e}`.

## Closures / Blocks

Pass anonymous functions to iterators using `do |params| ... end` syntax:

```winn
Enum.map(list) do |x|
  x * 2
end

Enum.filter(list) do |x|
  x > 0
end

Enum.reduce(list, 0) do |x, acc|
  x + acc
end
```

Combine with pipes:

```winn
list
  |> Enum.filter() do |x| x > 1 end
  |> Enum.map()    do |x| x * 10 end
```

### Pipe Assign (`|>=`)

Capture the result of a pipe chain into a variable:

```winn
[1, 2, 3, 4, 5]
  |> Enum.filter() do |x| x > 2 end
  |> Enum.map() do |x| x * 10 end
  |>= results

IO.puts("Got #{to_string(List.length(results))} results")
```

`|>=` assigns the pipe result to the named variable. The variable is available in subsequent expressions.

## Triple-Quoted Strings

Use `"""..."""` for multi-line strings. Common leading whitespace is stripped automatically, and embedded `"` quotes don't need escaping:

```winn
sql = """
  SELECT *
  FROM users
  WHERE active = true
  ORDER BY created_at DESC
"""

html = """
  <div class="card">
    <h1>#{title}</h1>
  </div>
"""
```

Triple-quoted strings support interpolation (`#{}`) just like regular strings.

## Structs

Define named struct types with `struct`:

```winn
module User
  struct [:name, :email, :age]
end
```

This generates:
- `User.new()` — returns a map with all fields set to `nil` and a `__struct__` key
- `User.new(%{name: "Alice", age: 30})` — merges attributes into the default map
- `User.__struct__()` — returns the module atom (for type identification)
- `User.__fields__()` — returns the list of field names

```winn
user = User.new(%{name: "Alice", age: 30})
user.name        # => "Alice"
user.__struct__  # => :user
```

Structs are maps with a `__struct__` key, so all Map functions work on them. You can define methods alongside the struct:

```winn
module User
  struct [:name, :email]

  def greet(user)
    "Hello, #{user.name}!"
  end
end
```

## Protocols

Protocols define interfaces that multiple struct types can implement. Dispatch is based on the `__struct__` key at runtime.

### Defining a Protocol

```winn
module Printable
  protocol do
    def to_s(value)
      "unknown"
    end
  end
end
```

### Implementing a Protocol

Use `impl ProtocolName do ... end` inside a struct module:

```winn
module User
  struct [:name, :email]

  impl Printable do
    def to_s(user)
      "User(#{user.name})"
    end
  end
end

module Post
  struct [:title]

  impl Printable do
    def to_s(post)
      "Post: #{post.title}"
    end
  end
end
```

### Using Protocols

Call the protocol function — dispatch happens automatically based on the struct type:

```winn
user = User.new(%{name: "Alice"})
post = Post.new(%{title: "Hello World"})

Printable.to_s(user)   # => "User(Alice)"
Printable.to_s(post)   # => "Post: Hello World"
```

Protocol implementations are registered at module load time. Multiple struct types can implement the same protocol.

## Standalone Lambdas

Create anonymous functions with `fn(params) => body end`:

```winn
double = fn(x) => x * 2 end
double(5)   # => 10

add = fn(a, b) => a + b end
add(3, 4)   # => 7

constant = fn() => 42 end
constant()  # => 42
```

Lambdas capture variables from their enclosing scope (closures):

```winn
def make_adder(n)
  fn(x) => x + n end
end

add_ten = make_adder(10)
add_ten(5)   # => 15
```

## For Comprehensions

Iterate over a list and transform each element:

```winn
for x in [1, 2, 3] do
  x * 10
end
# => [10, 20, 30]
```

Works with ranges:

```winn
for i in 1..5 do
  i * i
end
# => [1, 4, 9, 16, 25]
```

## Range Literals

Create a list of integers with `..`:

```winn
1..5        # => [1, 2, 3, 4, 5]
1..1        # => [1]
```

Ranges work anywhere a list is expected:

```winn
1..10
  |> Enum.filter() do |x| x > 5 end
  |> Enum.map() do |x| x * 2 end
# => [12, 14, 16, 18, 20]
```

## Map Field Access

Access map fields with dot notation:

```winn
user = %{name: "Alice", age: 30}
user.name   # => "Alice"
user.age    # => 30

resp = HTTP.get("https://api.example.com/data")
resp.status # => 200
resp.body   # => decoded JSON map
```

This is syntactic sugar for `maps:get(field, map)`.

## Type Conversion Builtins

These are available as bare function calls (no module prefix):

```winn
to_string(42)        # => "42"
to_string(:hello)    # => "hello"
to_integer("123")    # => 123
to_float(5)          # => 5.0
to_atom("hello")     # => :hello
inspect({:ok, 42})   # => "{ok,42}"
```

## Control Flow

### if/else

`if/else` is an expression — it returns a value.

```winn
if x > 0
  :positive
else
  :non_positive
end
```

`else` is optional:

```winn
if debug
  IO.puts("debug mode")
end
```

Use as an expression:

```winn
label = if count > 100
  "many"
else
  "few"
end
```

### switch

Multi-branch matching on a value:

```winn
switch status
  :active   => "Active"
  :inactive => "Inactive"
  _         => "Unknown"
end
```

Switch clauses support any pattern — atoms, integers, tuples, wildcards:

```winn
switch code
  200 => :ok
  404 => :not_found
  500 => :server_error
  _   => :unknown
end
```

For multiple expressions in a clause body, just use newlines:

```winn
switch status
  :active =>
    Logger.info("user is active")
    :ok
  :inactive =>
    Logger.warn("user inactive")
    :disabled
  _ => :unknown
end
```

The old `do...end` wrapper syntax also still works:

```winn
switch status
  :active => do
    Logger.info("user is active")
    :ok
  end
  _ => :unknown
end
```

### Guards

Use `when` to add conditions to function clauses and switch branches:

```winn
def divide(a, b) when b != 0
  a / b
end

def divide(_, 0)
  {:error, "division by zero"}
end
```

Guards on switch clauses:

```winn
switch value
  n when n > 0  => :positive
  n when n < 0  => :negative
  _             => :zero
end
```

Multiple guarded clauses are matched top-to-bottom:

```winn
def grade(score) when score >= 90
  :a
end

def grade(score) when score >= 80
  :b
end

def grade(score) when score >= 70
  :c
end

def grade(_)
  :f
end
```

### try/rescue

Handle exceptions with `try/rescue`:

```winn
try
  risky_operation()
rescue
  {:error, reason} => IO.puts("caught: " <> reason)
  _                => IO.puts("unknown error")
end
```

`try` is an expression — the last evaluated value is returned:

```winn
result = try
  dangerous_call()
rescue
  _ => :fallback_value
end
```

## Module Calls

Call functions on other modules with `.` notation:

```winn
IO.puts("Hello")
String.upcase(name)
Enum.map(list) do |x| x * 2 end
HTTP.get("https://api.example.com/data")
JWT.sign(%{user_id: 42}, secret)
Logger.info("request processed", %{duration_ms: 150})
```

## Comments

Line comments start with `#`:

```winn
# This is a comment
def greet(name)
  IO.puts("Hello, " <> name)  # inline comment
end
```

Block comments use `#| ... |#` and can span multiple lines:

```winn
#|
  This module handles user authentication.
  It supports JWT and session-based auth.
|#
module Auth
  def verify(token)
    # ...
  end
end
```

Block comments can also be used inline or to comment out code:

```winn
x = 42 #| temporary |# + 0
```

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

## Functions

Functions are defined with `def` and closed with `end`. The last expression in a function body is the return value.

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

Strings are UTF-8 binaries. Concatenate with `<>`:

```winn
"Hello, " <> "World!"
```

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

Comments start with `#`:

```winn
# This is a comment
def greet(name)
  IO.puts("Hello, " <> name)  # inline comment
end
```

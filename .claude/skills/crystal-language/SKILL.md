---
name: crystal-language
description: Crystal programming language reference for Amber developers — types, macros, concurrency, modules, blocks, generics, and Crystal-specific patterns
user-invocable: false
---

# Crystal Language Reference for Amber Developers

This skill covers the Crystal language features most relevant to understanding and working with the Amber framework. For complete language documentation, see the [Crystal Book](https://crystal-lang.org/reference/).

## Type System Overview

Crystal is a statically typed, compiled language with type inference. Types are known at compile time, but the compiler infers most types automatically.

### Classes

Classes are reference types allocated on the heap. They inherit from `Reference` by default.

```crystal
class Person
  property name : String
  property age : Int32

  def initialize(@name : String, @age : Int32)
  end

  def greet
    "Hi, I'm #{@name}"
  end
end

person = Person.new("Alice", 30)
```

### Structs

Structs are value types allocated on the stack, passed by copy. Use for small, immutable data.

```crystal
struct Point
  property x : Int32, y : Int32

  def initialize(@x : Int32, @y : Int32)
  end
end
```

**Key difference:** Structs are copied on assignment; classes are passed by reference. Structs cannot inherit from non-abstract structs.

The `record` macro simplifies struct definitions:
```crystal
record Point, x : Int32, y : Int32
```

### Modules

Modules serve as namespaces and mixins. They cannot be instantiated.

```crystal
module Validatable
  def valid?
    # ...
  end
end

class User
  include Validatable  # Adds instance methods
end
```

- `include` adds module methods as instance methods
- `extend` adds module methods as class methods
- `extend self` makes a module usable both as namespace and mixin

### Enums

Enums are named integer constants with type safety.

```crystal
enum Color
  Red    # 0
  Green  # 1
  Blue   # 2
end

# Flags enums use powers of 2
@[Flags]
enum Permissions
  Read   # 1
  Write  # 2
  Admin  # 4
end
```

### Generics

Types can be parameterized with type variables.

```crystal
class Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end

Box.new(42)      # Box(Int32)
Box.new("hello") # Box(String)
```

Generics work with classes, structs, and modules. Inheritance can specify or delegate type variables.

### Union Types

A variable can hold values of multiple types. The compiler tracks these as union types.

```crystal
value = rand < 0.5 ? 42 : "hello"
typeof(value) # => Int32 | String

# Nil unions are common
name : String? # Same as String | Nil
```

### Type Inference

Crystal infers types from assignments, method parameter restrictions, and default values. Instance variables require types to be determinable at compile time.

```crystal
class Config
  def initialize(@host : String, @port = 3000)
    # @host inferred as String (from type restriction)
    # @port inferred as Int32 (from literal default)
  end
end
```

## Blocks, Procs, and Closures

### Blocks

Blocks are inlined code passed to methods via `yield`. They have **zero overhead** -- the compiler inlines them.

```crystal
def twice(&)
  yield 1
  yield 2
end

twice { |i| puts i }
```

Amber DSLs use blocks extensively via `with ... yield` to change the default receiver:

```crystal
def configure(&)
  with self yield
end
```

### Procs

Procs are captured blocks -- they are closures with a reference to their environment.

```crystal
callback = ->(x : Int32) { x * 2 }
callback.call(5) # => 10

# Capture a method as a Proc
adder = ->add(Int32, Int32)
```

### Block Forwarding

Blocks can be captured and stored by giving the block parameter a name and type:

```crystal
def on_save(&block : -> Nil)
  @callback = block
end
```

## Macros (Compile-Time Metaprogramming)

Macros operate on AST nodes at compile time and generate code. They are essential for understanding Amber's DSLs.

### Basic Macros

```crystal
macro define_getter(name, type)
  def {{name.id}} : {{type}}
    @{{name.id}}
  end
end
```

- `{{expression}}` interpolates an AST node into the output
- `{% if %}`, `{% for %}` provide compile-time control flow
- `.id` converts a node to an identifier (strips quotes/symbols)
- `.stringify` converts to a string literal

### Compile-Time Hooks

These are critical for understanding Amber's inheritance-based patterns:

- **`inherited`** -- Invoked when a subclass is defined. `@type` is the child type.
- **`included`** -- Invoked when a module is included. `@type` is the including type.
- **`extended`** -- Invoked when a module is extended.
- **`finished`** -- Invoked after all types are fully defined. Use for cross-type introspection.
- **`method_missing`** -- Invoked for undefined method calls.
- **`method_added`** -- Invoked when a new method is defined.

### Macro Methods

A `def` containing `@type` in macro expressions is implicitly a macro def -- it is instantiated per concrete subtype:

```crystal
class Base
  def type_name
    {{ @type.name.stringify }}
  end
end

class Child < Base; end
Child.new.type_name # => "Child"
```

### Type Information in Macros

- `@type` -- The current type (always instance type)
- `@type.instance_vars` -- Instance variables
- `@type.methods` -- Defined methods
- `@type.ancestors` -- Ancestor chain
- `@top_level` -- Top-level namespace
- `@def` -- Current method info (or NilLiteral outside methods)

### Fresh Variables

Use `%name` for variables that won't conflict with the macro invocation scope:

```crystal
macro safe_swap(a, b)
  %temp = {{a}}
  {{a}} = {{b}}
  {{b}} = %temp
end
```

## Concurrency (Fibers and Channels)

Crystal uses cooperative concurrency with fibers (lightweight green threads) and channels for communication.

### Fibers

Fibers are lightweight execution units (~4KB initial stack, up to 8MB). They are cooperative -- they yield control explicitly at I/O boundaries.

```crystal
spawn do
  puts "Hello from a fiber"
end

# Fibers don't execute until the current fiber yields
Fiber.yield
# Or: sleep, channel operations, I/O
```

### Channels

Channels communicate data between fibers without shared memory.

```crystal
channel = Channel(String).new

spawn do
  channel.send("Hello")
end

message = channel.receive # Blocks until a value is sent
puts message # => "Hello"
```

**Buffered channels** allow sends without blocking up to the buffer capacity:

```crystal
ch = Channel(Int32).new(10) # Buffer of 10
```

### Concurrency Patterns in Amber

- **WebSocket channels** use fibers for each client connection
- **Background jobs** use fibers with work-stealing across idle web instances
- **I/O operations** (sockets, files) automatically yield the current fiber
- **Event loop** handles async I/O, timers, signals

## Error Handling

```crystal
begin
  risky_operation
rescue ex : MyError
  puts ex.message
rescue ex
  # Catch any exception
ensure
  # Always runs
end
```

**Convention:** Methods ending in `?` return nil instead of raising:
```crystal
array[4]  # Raises IndexError
array[4]? # Returns nil
```

## JSON::Serializable

Used extensively in Amber for JSON request/response handling:

```crystal
require "json"

class User
  include JSON::Serializable

  property name : String
  property email : String

  @[JSON::Field(key: "created_at")]
  property created_at : Time?
end

user = User.from_json(%q({"name": "Alice", "email": "a@b.com"}))
user.to_json # => serialized JSON
```

## Reference Documentation

For deeper coverage of specific topics, see the reference guides:

- `reference/language-overview.md` -- Type system, method dispatch, generics, modules, inheritance
- `reference/macros-guide.md` -- Macro definitions, compile-time hooks, macro methods, @type
- `reference/concurrency-guide.md` -- Fibers, spawn, channels, select, IO wait

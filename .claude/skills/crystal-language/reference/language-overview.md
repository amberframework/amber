# Crystal Language Overview

This reference covers Crystal's type system, method dispatch, generics, modules, and inheritance -- the foundations needed to understand Amber's architecture.

## Type Hierarchy

```
Object
  |
  +-- Reference (classes, heap-allocated, passed by reference)
  |     +-- Class
  |     +-- String
  |     +-- Array(T)
  |     +-- Hash(K, V)
  |
  +-- Value (structs, stack-allocated, passed by copy)
        +-- Struct
        |     +-- record types
        +-- Number
        |     +-- Int (Int8, Int16, Int32, Int64, Int128)
        |     +-- UInt (UInt8, UInt16, UInt32, UInt64, UInt128)
        |     +-- Float (Float32, Float64)
        +-- Bool
        +-- Char
        +-- Symbol
        +-- Enum
        +-- Tuple(*T)
        +-- NamedTuple(**T)
        +-- Pointer(T)
        +-- StaticArray(T, N)
```

## Classes

Classes are reference types. They inherit from `Reference` by default, are allocated on the heap, and are passed by reference.

```crystal
class Person
  # Instance variable with type restriction
  @name : String
  @age : Int32

  # Constructor shorthand: @name assigns to instance variable
  def initialize(@name : String, @age : Int32)
  end

  # Property macro generates getter and setter
  property email : String?

  # Getter only
  getter name : String

  # Setter only
  setter password : String?
end
```

### Inheritance

Single inheritance with `<`. Constructors are inherited unless overridden.

```crystal
class Employee < Person
  def initialize(@name : String, @age : Int32, @company : String)
  end

  # Call parent with super
  def greet
    super  # Passes same args automatically
  end
end
```

### Abstract Classes and Methods

```crystal
abstract class Shape
  abstract def area : Float64

  def description
    "A shape with area #{area}"
  end
end

class Circle < Shape
  def initialize(@radius : Float64)
  end

  def area : Float64
    Math::PI * @radius ** 2
  end
end
```

### Virtual Types

When Crystal sees a union of related types, it creates a virtual type (`Parent+`):

```crystal
shape = rand < 0.5 ? Circle.new(5.0) : Rectangle.new(3.0, 4.0)
typeof(shape) # => Shape+  (Shape or any subtype)
```

## Modules

Modules cannot be instantiated. They serve as namespaces and mixins.

### As Namespaces

```crystal
module Amber
  module Controller
    class Base
    end
  end
end
```

### As Mixins (include/extend)

`include` adds methods as instance methods. The module is prepended to the ancestor chain:

```crystal
module Serializable
  def to_json
    # ...
  end
end

class User
  include Serializable
end

User.new.to_json  # Instance method from module
```

`extend` adds methods as class methods:

```crystal
module ClassMethods
  def find(id)
    # ...
  end
end

class User
  extend ClassMethods
end

User.find(1)  # Class method from module
```

### Module Type Checking

Modules can be used as type restrictions:

```crystal
module Printable; end

class Doc
  include Printable
end

def print_it(item : Printable)
  # Accepts any type that includes Printable
end
```

## Method Dispatch and Overloading

Crystal resolves method calls at compile time based on argument types, count, and restrictions.

```crystal
class Converter
  def convert(value : String)
    value.to_i
  end

  def convert(value : Int32)
    value.to_s
  end

  def convert(value : String, base : Int32)
    value.to_i(base)
  end
end
```

### Type Restrictions

```crystal
def process(x : Int32)           # Exact type
def process(x : Int32 | String)  # Union
def process(x : Enumerable)      # Any type including module
def process(x : _)               # Any type (underscore)
def process(x : T) forall T      # Generic / free variable
```

### Return Type Restrictions

```crystal
def name : String
  @name
end

def find(id) : User?  # Returns User or nil
  # ...
end
```

## Generics

### Generic Classes

```crystal
class Cache(K, V)
  def initialize
    @store = Hash(K, V).new
  end

  def get(key : K) : V?
    @store[key]?
  end

  def set(key : K, value : V)
    @store[key] = value
  end
end

cache = Cache(String, Int32).new
cache.set("count", 42)
```

### Generic Modules

```crystal
module Comparable(T)
  abstract def <=>(other : T) : Int32

  def <(other : T)
    (self <=> other) < 0
  end
end
```

### Splatted Generics

```crystal
class Tuple(*T)
  # Variable number of type parameters
end
```

### Type Inference with Generics

The compiler can infer generic type arguments from constructor parameters:

```crystal
Box.new(42)      # Inferred as Box(Int32)
Box.new("hello") # Inferred as Box(String)
```

## Union Types

Union types arise from conditional assignments and are tracked at compile time.

```crystal
value : Int32 | String | Nil

# Narrowing with is_a?
if value.is_a?(String)
  value.upcase  # OK: compiler knows it's String here
end

# Narrowing with responds_to?
if value.responds_to?(:upcase)
  value.upcase
end

# Nil check narrowing
if value
  # value is Int32 | String (Nil excluded)
end
```

### Nilable Shorthand

`T?` is sugar for `T | Nil`:

```crystal
name : String?  # Same as String | Nil
```

## Instance Variable Type Inference

Crystal requires that instance variable types be determinable at compile time. The compiler uses these rules (in order of priority):

1. **Literal assignment**: `@x = 0` infers `Int32`
2. **Type.new**: `@x = Array(Int32).new` infers `Array(Int32)`
3. **Parameter restriction**: `def initialize(@x : String)` infers `String`
4. **Class method return type**: `@x = Foo.default` (if return type is annotated)
5. **Default parameter**: `def initialize(@x = "default")` infers `String`

If none apply, use explicit type restriction: `@x : SomeType`.

## Visibility

```crystal
class Foo
  private def secret
    # Only callable from within this type
  end

  protected def internal
    # Callable from this type and subtypes
  end

  def public_method
    # Default: callable from anywhere
  end
end
```

## Constants

```crystal
MAX_SIZE = 100
PI = 3.14159

# Constants can be any type
COLORS = ["red", "green", "blue"]

# Type constants
alias UserID = Int64
```

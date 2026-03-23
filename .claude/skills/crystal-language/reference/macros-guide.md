# Crystal Macros Guide

Macros are compile-time metaprogramming in Crystal. They receive AST nodes and produce code that is pasted into the program. Understanding macros is essential for working with Amber's DSLs (routing, pipelines, callbacks, server configuration).

## Macro Basics

### Defining and Using Macros

```crystal
macro define_method(name, body)
  def {{name.id}}
    {{body}}
  end
end

define_method greet, "Hello!"
greet # => "Hello!"
```

### Interpolation

`{{expression}}` pastes an AST node into the output. Use `.id` to convert symbols/strings to identifiers:

```crystal
macro attr(name, type)
  @{{name.id}} : {{type}}

  def {{name.id}} : {{type}}
    @{{name.id}}
  end

  def {{name.id}}=(value : {{type}})
    @{{name.id}} = value
  end
end
```

### Compile-Time Control Flow

```crystal
macro generate(flag)
  {% if flag %}
    def enabled?; true; end
  {% else %}
    def enabled?; false; end
  {% end %}
end
```

### Iteration

```crystal
macro define_methods(*names)
  {% for name, index in names %}
    def {{name.id}}
      {{index}}
    end
  {% end %}
end

define_methods foo, bar, baz
foo # => 0
bar # => 1
```

Works with `ArrayLiteral`, `HashLiteral`, `TupleLiteral`, and ranges.

## Compile-Time Hooks

Hooks are special macros invoked automatically by the compiler at specific points. They are heavily used by Amber and Grant.

### `inherited`

Invoked when a subclass is defined. `@type` is the child type.

```crystal
class Base
  macro inherited
    def self.type_name
      {{@type.name.stringify}}
    end
  end
end

class Child < Base; end
Child.type_name # => "Child"
```

**In Amber:** Used by `Amber::Controller::Base` to register controllers and set up route helpers for each subclass.

### `included`

Invoked when a module is included. `@type` is the including type.

```crystal
module Trackable
  macro included
    @@tracked_instances = [] of {{@type}}

    def self.all
      @@tracked_instances
    end
  end
end
```

**In Amber:** Used by modules like `JSON::Serializable` and Grant's model mixins to inject fields and methods.

### `extended`

Invoked when a module is extended. `@type` is the extending type.

### `finished`

Invoked after all types are fully defined (including reopened classes). Essential for cross-type introspection:

```crystal
class Registry
  macro finished
    # Now all subclasses are known
    TYPES = [
      {% for type in @type.all_subclasses %}
        {{type}},
      {% end %}
    ]
  end
end
```

**In Amber:** Used by the router to finalize route tables after all routes are defined.

### `method_missing`

Invoked for undefined method calls. Generates code to handle them:

```crystal
class DynamicProxy
  macro method_missing(call)
    puts "Called: {{call.name.id}} with {{call.args.size}} args"
  end
end
```

### `method_added`

Invoked when a new method is defined in the current scope:

```crystal
macro method_added(method)
  {% puts "Registered: #{method.name}" %}
end
```

## Macro Methods (Implicit Macro Defs)

A `def` that contains `@type` in macro expressions is implicitly a macro def. It gets instantiated for each concrete subtype:

```crystal
class Base
  def instance_var_names
    {{ @type.instance_vars.map &.name.stringify }}
  end
end

class User < Base
  def initialize(@name : String, @age : Int32)
  end
end

User.new("Alice", 30).instance_var_names # => ["name", "age"]
```

**Important:** Method arguments are NOT available at macro expansion time in macro defs. Only `@type` and `@def` are available.

## Type Information Available in Macros

### @type Methods

| Method | Returns | Example |
|--------|---------|---------|
| `@type.name` | Type name as `Path` | `User` |
| `@type.stringify` | Name as `StringLiteral` | `"User"` |
| `@type.instance_vars` | Array of `MetaVar` | `[name, age]` |
| `@type.methods` | Array of `Def` | `[greet, save]` |
| `@type.ancestors` | Array of `TypeNode` | `[Base, Reference, Object]` |
| `@type.all_subclasses` | All subclasses | `[Admin, Guest]` |
| `@type.has_constant?(name)` | Bool | check for constants |
| `@type.class_vars` | Class variables | `[@@count]` |
| `@type.superclass` | Parent type | `Base` |
| `@type.abstract?` | Bool | is abstract? |

### @def Methods

Available inside method bodies:

| Method | Returns |
|--------|---------|
| `@def.name` | Method name |
| `@def.args` | Method arguments |
| `@def.receiver` | Explicit receiver (for `self.method`) |
| `@def.return_type` | Return type restriction |

### Top-Level

`@top_level` gives access to the top-level namespace as a `TypeNode`.

## Fresh Variables

Fresh variables prevent name collisions between macro-generated code and the calling scope:

```crystal
macro swap(a, b)
  %temp = {{a}}
  {{a}} = {{b}}
  {{b}} = %temp
end
```

`%temp` generates a unique variable name at each macro expansion.

Indexed fresh variables for loops:

```crystal
macro multi_swap(*pairs)
  {% for pair, i in pairs %}
    %temp{i} = {{pair[0]}}
    {{pair[0]}} = {{pair[1]}}
    {{pair[1]}} = %temp{i}
  {% end %}
end
```

## Macro Scope and Visibility

- **Top-level macros** are visible everywhere (unless `private`)
- **Class/module macros** are visible in that scope and subclasses
- Macros are looked up in the ancestor chain, just like methods
- `with ... yield` blocks can access macros from the yielded object's ancestors

## Environment and Compilation Context

```crystal
# Check compile-time flags
{% if flag?(:linux) %}
  # Linux-specific code
{% end %}

# Environment variables at compile time
{% if env("AMBER_ENV") == "production" %}
  # Production-specific code
{% end %}

# Run external commands at compile time
{% system("date").stringify %}

# Read files at compile time
{{ read_file("VERSION").stringify }}
```

## Common Patterns in Amber

### DSL via `with ... yield`

Amber's server configuration DSL uses `with self yield` to make macros available inside blocks:

```crystal
Amber::Server.configure do
  # These calls resolve to macros on the server's class
  pipeline :web do
    plug Amber::Pipe::Logger.new
  end

  routes :web do
    get "/", HomeController, :index
  end
end
```

### Register-on-Inherit Pattern

```crystal
abstract class BaseJob
  REGISTRY = [] of BaseJob.class

  macro inherited
    REGISTRY << {{@type}}
  end
end
```

### Property Generation with Validation

```crystal
macro validated_property(name, type, **options)
  @{{name.id}} : {{type}}

  def {{name.id}} : {{type}}
    @{{name.id}}
  end

  def {{name.id}}=(value : {{type}})
    {% if options[:min] %}
      raise "Too small" if value < {{options[:min]}}
    {% end %}
    @{{name.id}} = value
  end
end
```

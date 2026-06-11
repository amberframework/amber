# Schema API

The Schema API provides type-safe, validated parameter handling for Amber controllers. It replaces manual `params["key"]` access with declarative schema definitions that include type coercion, validation, and structured error reporting. The Schema API is opt-in and backward compatible -- existing `params` usage continues to work.

## Quick Start

```crystal
class CreateUserSchema < Amber::Schema::Definition
  field :name, String, required: true
  field :email, String, required: true, format: "email"
  field :age, Int32, required: true, min: 0, max: 150
end

# In a controller action
def create
  schema = CreateUserSchema.new(context.params.to_h)
  result = schema.validate

  if result.success?
    name = schema.name.not_nil!
    email = schema.email.not_nil!
    age = schema.age.not_nil!
    # Create the user...
  else
    flash[:error] = result.error_messages.join(", ")
    redirect_to "/users/new"
  end
end
```

## Defining Schemas

Schemas are defined by inheriting from `Amber::Schema::Definition` and using the `field` macro.

### Field Types

| DSL Macro | Crystal Type | Description |
|-----------|-------------|-------------|
| `field :name, String` | `String` | String values |
| `field :age, Int32` | `Int32` | 32-bit integers |
| `field :count, Int64` | `Int64` | 64-bit integers |
| `field :price, Float64` | `Float64` | 64-bit floats |
| `field :active, Bool` | `Bool` | Boolean values |
| `field :tags, Array(String)` | `Array(String)` | Arrays with typed elements |
| `field :metadata, Hash(String, JSON::Any)` | `Hash` | Hash/object fields |
| `field :created_at, Time` | `Time` | ISO8601 time values |

### DSL Shorthand (via Amber::Schema::DSL)

When you include `Amber::Schema::DSL` in your schema, you get shorthand macros:

```crystal
class UserSchema < Amber::Schema::Definition
  include Amber::Schema::DSL

  string :name, required: true
  string :email, required: true
  integer :age
  float :score
  boolean :active
  array :tags, of: String
  datetime :created_at
end
```

### Required Fields

```crystal
field :name, String, required: true
# Validation will fail if "name" is missing from the input data
```

### Default Values

```crystal
field :role, String, default: "user"
field :active, Bool, default: true
```

### Field Options

Fields support inline constraint options:

```crystal
# Range constraints (numeric fields)
field :age, Int32, min: 0, max: 150
field :price, Float64, min: 0.0

# Length constraints (string fields)
field :name, String, min_length: 1, max_length: 100
field :bio, String, max_length: 500

# Format validation
field :email, String, format: "email"
field :website, String, format: "url"
field :uuid, String, format: "uuid"

# Enum validation
field :status, String, enum: ["active", "inactive", "pending"]

# Pattern validation (regex)
field :phone, String, pattern: "^\\+?[1-9]\\d{1,14}$"
```

### Built-in Format Validators

| Format | Description |
|--------|-------------|
| `"email"` | Standard email address pattern |
| `"url"` / `"uri"` | Valid URL with scheme and host |
| `"uuid"` | UUID format |
| `"iso8601"` / `"datetime"` | ISO8601 datetime string |
| `"date"` | Date in YYYY-MM-DD format |
| `"time"` | Time in HH:MM or HH:MM:SS format |
| `"ipv4"` | IPv4 address |
| `"ipv6"` | IPv6 address |
| `"hostname"` | Valid hostname |

## Validation

### Running Validation

```crystal
schema = CreateUserSchema.new(data)

# Legacy result API
result = schema.validate
if result.success?
  # Access validated data
  puts result.data  # => Hash(String, JSON::Any)
else
  puts result.error_messages  # => Array(String)
  puts result.errors_by_field # => Hash(String, Array(Error))
end

# Typed result API
typed_result = schema.validate_typed
case typed_result
when Amber::Schema::Success
  data = typed_result.value
when Amber::Schema::Failure
  errors = typed_result.error.errors
end
```

### Accessing Typed Fields

After creating a schema instance, fields are accessible as typed getter methods:

```crystal
schema = CreateUserSchema.new(data)
result = schema.validate

if result.success?
  name = schema.name    # => String?
  age = schema.age      # => Int32?
  email = schema.email  # => String?
end
```

### Custom Validators

Add custom validation logic using the `validate` macro:

```crystal
class PasswordChangeSchema < Amber::Schema::Definition
  field :password, String, required: true, min_length: 8
  field :password_confirmation, String, required: true

  validate do |context|
    password = context.field_value("password")
    confirmation = context.field_value("password_confirmation")

    if password && confirmation && password != confirmation
      context.add_error(
        Amber::Schema::CustomValidationError.new(
          "password_confirmation",
          "Password confirmation does not match"
        )
      )
    end
  end
end
```

### Conditional Validation

Use `requires_together` and `requires_one_of` for cross-field constraints:

```crystal
class AddressSchema < Amber::Schema::Definition
  field :street, String
  field :city, String
  field :state, String
  field :zip, String

  # All address fields must be present together
  requires_together :street, :city, :state, :zip
end

class AuthSchema < Amber::Schema::Definition
  field :email, String
  field :phone, String
  field :oauth_token, String

  # Exactly one authentication method required
  requires_one_of :email, :phone, :oauth_token
end
```

### Nested Schemas

Validate nested objects using the `nested` macro:

```crystal
class AddressSchema < Amber::Schema::Definition
  field :street, String, required: true
  field :city, String, required: true
  field :zip, String, required: true
end

class OrderSchema < Amber::Schema::Definition
  field :product_id, Int64, required: true
  field :quantity, Int32, required: true, min: 1

  nested :shipping_address, AddressSchema
end
```

Nested schema errors are prefixed with the parent field name (e.g., `"shipping_address.city"`).

## Type Coercion

The Schema API automatically coerces values from their source types to the declared field types. This is particularly useful when dealing with form data (where everything is a string) or JSON payloads.

### Coercion Rules

| Source | Target | Behavior |
|--------|--------|----------|
| String `"42"` | Int32 | Parsed to `42` |
| String `"3.14"` | Float64 | Parsed to `3.14` |
| String `"true"` | Bool | Coerced to `true` |
| Int `42` | String | Converted to `"42"` |
| String (ISO8601) | Time | Parsed to Time |
| String (UUID) | UUID | Parsed and validated |
| String `"a,b,c"` | Array(String) | Split on commas |

### Boolean Coercion

The following string values are recognized as `true`: `"true"`, `"1"`, `"yes"`, `"y"`, `"on"`, `"t"`, `"enabled"`, `"active"`.

The following are recognized as `false`: `"false"`, `"0"`, `"no"`, `"n"`, `"off"`, `"f"`, `"disabled"`, `"inactive"`.

### Custom Type Coercion

Register custom coercion functions for application-specific types:

```crystal
Amber::Schema::TypeCoercion.register("Money") do |value|
  if str = value.as_s?
    # Parse "$1,234.56" to cents
    cents = str.gsub(/[$,]/, "").to_f64 * 100
    JSON::Any.new(cents.to_i64)
  end
end
```

## Parsers

The Schema API includes parsers for multiple content types:

| Content Type | Parser |
|-------------|--------|
| `application/json` | JSONParser |
| `application/x-www-form-urlencoded` | QueryParser |
| `multipart/form-data` | MultipartParser |
| `application/xml`, `text/xml` | XMLParser |

### Content-Type Based Parsing

The `Parser::ParserRegistry` automatically selects the correct parser based on the request's Content-Type header:

```crystal
data = Amber::Schema::Parser::ParserRegistry.parse_request(context.request)
schema = MySchema.new(data)
```

## Error Types

| Error Class | Code | Description |
|------------|------|-------------|
| `RequiredFieldError` | `required_field_missing` | Required field not present |
| `TypeMismatchError` | `type_mismatch` | Value cannot be coerced to declared type |
| `InvalidFormatError` | `invalid_format` | Value does not match format constraint |
| `RangeError` | `out_of_range` | Numeric value outside min/max bounds |
| `LengthError` | `invalid_length` | String length outside min_length/max_length |
| `CustomValidationError` | (custom) | Application-defined validation failure |

### Error Structure

Each error contains:

```crystal
error.field    # => "email"
error.message  # => "Field 'email' has invalid format. Expected email"
error.code     # => "invalid_format"
error.details  # => Hash with additional context (optional)
error.to_h     # => Hash for JSON serialization
```

## Result Types

### LegacyResult (Backward Compatible)

```crystal
result = schema.validate
result.success?          # => Bool
result.failure?          # => Bool
result.data              # => Hash(String, JSON::Any)?
result.errors            # => Array(Error)
result.warnings          # => Array(Warning)
result.error_messages    # => Array(String)
result.errors_by_field   # => Hash(String, Array(Error))
result.to_h              # => Hash for JSON serialization
```

### Typed Result (Monadic)

```crystal
result = schema.validate_typed

# Pattern matching
result
  .on_success { |data| puts "Valid: #{data}" }
  .on_failure { |error| puts "Invalid: #{error.messages}" }

# Functor map
result.map { |data| transform(data) }

# Monadic bind
result.flat_map { |data| further_validate(data) }
```

## Controller Integration

### Using with Request Params

```crystal
def create
  # Convert Amber params to a Hash(String, JSON::Any)
  data = {} of String => JSON::Any
  context.params.each do |key, value|
    data[key] = JSON::Any.new(value)
  end

  schema = CreateUserSchema.new(data)
  result = schema.validate

  if result.success?
    # Use typed accessors
    user = User.create!(
      name: schema.name.not_nil!,
      email: schema.email.not_nil!
    )
    redirect_to "/users/#{user.id}"
  else
    flash[:error] = result.error_messages.join(", ")
    redirect_to "/users/new"
  end
end
```

### JSON API Pattern

```crystal
def create
  data = Amber::Schema::Parser::ParserRegistry.parse_request(context.request)
  schema = CreateUserSchema.new(data)
  result = schema.validate

  if result.success?
    user = User.create!(name: schema.name.not_nil!, email: schema.email.not_nil!)
    respond_with { json({id: user.id, name: user.name}) }
  else
    context.response.status_code = 422
    respond_with { json(result.to_h) }
  end
end
```

## Schema Introspection

Schemas support compile-time and runtime introspection:

```crystal
CreateUserSchema.field_names          # => ["name", "email", "age"]
CreateUserSchema.required_field_names # => ["name", "email", "age"]
CreateUserSchema.has_field?("name")   # => true
CreateUserSchema.has_conditionals?    # => false
```

## Source Files

- `src/amber/schema.cr` -- Module entry point
- `src/amber/schema/definition.cr` -- Base Definition class with field macro and validation
- `src/amber/schema/dsl.cr` -- DSL shorthand macros (string, integer, float, etc.)
- `src/amber/schema/request_schema.cr` -- RequestSchema for request validation
- `src/amber/schema/result.cr` -- LegacyResult, Success/Failure, ValidationFailure
- `src/amber/schema/errors.cr` -- Error type hierarchy
- `src/amber/schema/validator.cr` -- Validator base classes (Context, Custom, Composite, Conditional)
- `src/amber/schema/type_coercion.cr` -- Type coercion system
- `src/amber/schema/parser.cr` -- Parser base, ParserRegistry, TypeCoercion parser
- `src/amber/schema/parsers/json_parser.cr` -- JSON content parser
- `src/amber/schema/parsers/query_parser.cr` -- URL-encoded form parser
- `src/amber/schema/parsers/multipart_parser.cr` -- Multipart form data parser
- `src/amber/schema/parsers/xml_parser.cr` -- XML content parser
- `src/amber/schema/validators/` -- Built-in validators (required, type, format, length, range, enum, pattern)

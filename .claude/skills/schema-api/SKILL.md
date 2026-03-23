---
name: amber-schema-api
description: Amber V2 Schema API — request validation, type coercion, field definitions, validators, parsers, controller integration
user-invocable: false
---

# Amber V2 Schema API

The Schema API replaces the old `Amber::Validators` system with typed field definitions, automatic type coercion, structured error responses, and multi-format request parsing. It is automatically included in all Amber controllers.

## Schema::Definition

`Amber::Schema::Definition` is the base class for all schemas. Subclass it to define typed, validated data structures.

```crystal
class CreateUserSchema < Amber::Schema::Definition
  field email, String, required: true, format: "email"
  field password, String, required: true, min_length: 8
  field name, String
  field age, Int32, min: 18, max: 120
  field role, String, default: "user", enum: ["user", "admin", "moderator"]
end
```

Each `field` macro:

- Registers the field in `@@fields` with its type, constraints, and source
- Generates a typed getter method (returns `Type?`, using type coercion internally)
- Adds the field to `@@required_fields` when `required: true`

Instantiate with raw data and call `validate`:

```crystal
data = {"email" => JSON::Any.new("alice@example.com"), "password" => JSON::Any.new("secret123")}
schema = CreateUserSchema.new(data)
result = schema.validate

if result.success?
  email = schema.email   # => "alice@example.com" (String?)
  age = schema.age       # => nil (optional, not provided)
else
  result.errors.each { |e| puts "#{e.field}: #{e.message}" }
end
```

### Nested Schemas

Use `nested` to embed one schema inside another. Errors from the nested schema are prefixed with the parent field name.

```crystal
class AddressSchema < Amber::Schema::Definition
  field street, String, required: true
  field city, String, required: true
  field zip, String, required: true, pattern: "^\\d{5}$"
end

class CreateOrderSchema < Amber::Schema::Definition
  field customer_email, String, required: true, format: "email"
  nested shipping_address, AddressSchema
end
```

The `nested` macro defines a `Hash(String, JSON::Any)` field and a `shipping_address_schema` getter that returns the validated nested `AddressSchema` instance. Nested validation errors appear as `"shipping_address.city"`, `"shipping_address.zip"`, etc.

### Field Co-presence and Mutual Exclusion

```crystal
class PaymentSchema < Amber::Schema::Definition
  field credit_card_number, String
  field credit_card_expiry, String
  field credit_card_cvv, String
  field bank_account, String

  # All three credit card fields must appear together
  requires_together credit_card_number, credit_card_expiry, credit_card_cvv

  # Must provide either card or bank account, not both
  requires_one_of credit_card_number, bank_account
end
```

### Conditional Validation

`when_field` applies validation only when a specific field has a specific value. `when_present` applies when the field exists at all.

```crystal
class RegistrationSchema < Amber::Schema::Definition
  field account_type, String, required: true
  field company_name, String

  when_field account_type, "business" do
    field company_name, String, required: true
    field tax_id, String, required: true
  end

  when_present :company_name do
    field company_size, Int32, required: true
  end
end
```

### Custom Validators

Use the `validate` macro with a method name or block:

```crystal
class TransferSchema < Amber::Schema::Definition
  field amount, Float64, required: true
  field source_account, String, required: true
  field target_account, String, required: true

  validate :check_different_accounts

  def check_different_accounts
    if source_account == target_account
      @errors << Amber::Schema::CustomValidationError.new(
        "target_account", "Source and target accounts must differ", "same_account"
      )
    end
  end
end
```

Or inline with a block receiving `Validator::Context`:

```crystal
validate do |context|
  if context.field_value("start_date") && context.field_value("end_date")
    # custom logic using context.add_error(...)
  end
end
```

### Parameter Source Blocks

Declare which HTTP source a field comes from:

```crystal
class UpdatePostSchema < Amber::Schema::Definition
  from_path do
    field id, Int32, required: true
  end

  from_query do
    field preview, Bool, default: false
  end

  from_body do
    field title, String, required: true
    field content, String, required: true
  end

  from_header do
    field x_api_version, String
  end
end
```

### Content Type and Success/Failure Type Declaration

```crystal
class MySchema < Amber::Schema::Definition
  content_type "application/json"
  validates_to UserRequest, UserValidationError
end
```

### Introspection

```crystal
CreateUserSchema.field_names          # => ["email", "password", "name", "age", "role"]
CreateUserSchema.required_field_names # => ["email", "password"]
CreateUserSchema.has_field?("email")  # => true
CreateUserSchema.uses_body_params?    # => true
CreateUserSchema.uses_query_params?   # => false
CreateUserSchema.has_conditionals?    # => false
CreateUserSchema.conditionals         # => Array(ConditionalGroup)
```

## RequestSchema

`Amber::Schema::RequestSchema` extends `Definition` for request-specific workflows. It adds a two-phase `parse` method that validates first, then coerces all field values according to their declared types and applies default values.

```crystal
class SearchSchema < Amber::Schema::RequestSchema
  field query, String, required: true
  field page, Int32, default: 1
  field per_page, Int32, default: 20
end

schema = SearchSchema.new(data)
result = schema.parse(data)

if result.success?
  page = result.data.not_nil!["page"].as_i  # Int, not String
end
```

The `validate(data)` method on `RequestSchema` explicitly uses `Validator::Required` and `Validator::Type` instances, then runs field-specific validators and custom validators. The `parse(data)` method calls `validate` first, then applies `Parser::TypeCoercion` to each field.

## Field Types and Type Coercion

The `TypeCoercion` module handles conversion from raw input (typically strings from HTTP) to Crystal types.

### Supported Types

| Declared Type | Accepts | Coerces From |
|---|---|---|
| `String` | Any value | Numbers, booleans via `.to_s` |
| `Int32` | Integers in Int32 range | String digits, Int64, whole floats |
| `Int64` | Integers | String digits, Int32, whole floats |
| `Float32` | Floats | String decimals, integers |
| `Float64` | Floats | String decimals, integers |
| `Bool` | true/false | `"true"`, `"1"`, `"yes"`, `"on"`, `"t"`, `"enabled"`, `"active"` and inverses; integers 0/1; floats 0.0/1.0 |
| `Time` | ISO8601 strings | Unix timestamps (Int), 16 date/time string formats |
| `UUID` | UUID strings | Validates standard UUID format |
| `Array(T)` | JSON arrays | Comma-separated strings (for simple types), single values wrapped in array, JSON string of array |
| `Hash(String, T)` | JSON objects | JSON string of object |

### Registering Custom Coercions

```crystal
Amber::Schema::TypeCoercion.register("Money") do |value|
  if str = value.as_s?
    cents = str.gsub(/[$,]/, "").to_f64 * 100
    JSON::Any.new(cents.to_i64)
  end
end

Amber::Schema::TypeCoercion.clear_custom_coercions
```

### Checking Coercibility

```crystal
Amber::Schema::TypeCoercion.can_coerce?(JSON::Any.new("42"), "Int32")  # => true
Amber::Schema::TypeCoercion.can_coerce?(JSON::Any.new("abc"), "Int32") # => false
Amber::Schema::TypeCoercion.coercion_error("age", value, "Int32")      # => CoercionError struct
```

## Validators

All validators extend `Amber::Schema::Validator::Base` and implement `validate(context : Context) : Nil`. The `Context` provides `field_exists?`, `field_value`, `add_error`, and `add_warning`.

### Required

Ensures the field is present, non-nil, and non-empty-string.

```crystal
field email, String, required: true
```

Standalone class: `Validator::Required.new(field_name)`.

### Length

Validates string or array length (uses `.size`).

```crystal
field username, String, required: true, min_length: 3, max_length: 20
```

Standalone validator classes: `Validator::Length.new(field, min, max)`, `Validator::MinLength.new(field, min)`, `Validator::MaxLength.new(field, max)`.

### Format

Built-in format validators for common patterns:

```crystal
field email, String, format: "email"
field website, String, format: "url"
field id, String, format: "uuid"
field birthday, String, format: "date"          # YYYY-MM-DD
field created_at, String, format: "datetime"    # ISO8601
field start_time, String, format: "time"        # HH:MM:SS
field server_ip, String, format: "ipv4"
field server_ipv6, String, format: "ipv6"
field host, String, format: "hostname"
```

The `Validator::Format` class supports `FormatType` enum: `Email`, `URL`, `UUID`, `Date`, `DateTime`, `Time`, `IPv4`, `IPv6`, `Hostname`, `Phone`, `Custom`. Custom format strings passed as the `format:` option on a field are interpreted as regex patterns in the `Definition#validate_format` method.

### Range

Validates numeric bounds.

```crystal
field age, Int32, required: true, min: 0, max: 150
field price, Float64, min: 0.01
```

Standalone classes: `Validator::Range.new(field, min, max)`, `Validator::Min.new(field, min)`, `Validator::Max.new(field, max)`. All accept `Float64` bounds and work with both Int and Float values.

### Pattern

Validates string against a regex.

```crystal
field phone, String, pattern: "^\\+?[1-9]\\d{5,14}$"
```

Standalone class: `Validator::Pattern.new(field, pattern : Regex, message : String? = nil)`.

### Enum

Restricts to a set of allowed values.

```crystal
field status, String, enum: ["active", "inactive", "pending"]
```

Standalone class: `Validator::Enum.new(field, allowed_values)`. Accepts `Array(String)`, `Array(Int32)`, or `Array(Float64)`. String enums allow coercion (value converted to string for comparison). Numeric enums use strict type matching.

### Type

Validates that the raw JSON value matches the declared type. Used internally during field validation. Handles `String`, `Int32`, `Int64`, `Float32`, `Float64`, `Bool`, `Array(*)`, `Hash(*)`, and `Time`.

### Composite and Conditional Validators

```crystal
# Run multiple validators as one unit
composite = Validator::Composite.new([validator_a, validator_b])

# Run validator only when condition is met
conditional = Validator::Conditional.new(
  ->(ctx : Validator::Context) { ctx.field_exists?("password") },
  password_confirmation_validator
)
```

## Parsers

### ParserRegistry

Automatically selects the right parser based on `Content-Type`. Default registrations:

| Content-Type | Parser |
|---|---|
| `application/json`, `text/json` | JSONParser |
| `application/x-www-form-urlencoded`, `multipart/form-data` | QueryParser / MultipartParser |
| `application/xml`, `text/xml`, `application/xhtml+xml` | XMLParser |

```crystal
data = Amber::Schema::Parser::ParserRegistry.parse_request(request)
```

If the content type is unrecognized, the registry inspects the body to detect JSON (starts with `{` or `[`) or XML (starts with `<`).

### JSONParser

Parses JSON bodies and form-encoded params into `Hash(String, JSON::Any)`.

```crystal
# From JSON string
data = Amber::Schema::Parser::JSONParser.parse_string(json_body)

# From HTTP request
data = Amber::Schema::Parser::JSONParser.parse_request(request)

# From HTTP::Params (handles bracket and dot notation nesting)
data = Amber::Schema::Parser::JSONParser.parse_params(request.query_params)

# With schema for field aliasing via `as` option
data = Amber::Schema::Parser::JSONParser.extract_fields(json, schema)
```

Supports nested bracket notation (`user[profile][name]`), dot notation (`user.profile.name`), array notation (`tags[]`), indexed arrays (`items[0]`), sparse arrays, and auto-detection of booleans, numbers, null, and embedded JSON in string values.

### QueryParser

Parses URL query strings and form-encoded bodies into nested hashes.

```crystal
data = Amber::Schema::Parser::QueryParser.parse_query_string("page=1&filter[status]=active")
# => {"page" => 1, "filter" => {"status" => "active"}}

# Reverse conversion
query = Amber::Schema::Parser::QueryParser.to_query_string(data)
```

### MultipartParser

Handles `multipart/form-data` with file upload support.

```crystal
data = Amber::Schema::Parser::MultipartParser.parse_multipart_request(request)
```

File fields are represented as hashes with keys: `filename`, `content_type`, `size`, `content`, `headers`.

File validation options on schema fields:

```crystal
field avatar, Hash(String, JSON::Any), required: true,
  max_size: 5_000_000_i64,
  allowed_types: ["image/jpeg", "image/png"],
  allowed_extensions: [".jpg", ".jpeg", ".png"],
  filename_pattern: "^[a-zA-Z0-9_.-]+$"
```

The `FileUploadValidator.validate_file` class method checks these constraints and returns an array of errors.

### XMLParser

Parses XML bodies into flat hash structures. Elements become dot-delimited keys, attributes use `@` notation.

```crystal
data = Amber::Schema::Parser::XMLParser.parse_string(xml_body)
# <user><name>Alice</name></user>
# => {"user.name" => "Alice"}

# XPath-based extraction with schema
data = Amber::Schema::Parser::XMLParser.extract_fields_with_schema(xml_string, schema)

# Namespace-aware parsing
data = Amber::Schema::Parser::XMLParser.parse_with_namespaces(xml_string, {"ns" => "http://example.com"})
```

The `XPathContext` class supports queries like `//element`, `//element/@attr`, and namespace-prefixed elements.

### Sanitizer

Transforms string values with configurable options:

```crystal
sanitizer = Amber::Schema::Parser::Sanitizer.for_text      # trim, normalize whitespace, strip HTML
sanitizer = Amber::Schema::Parser::Sanitizer.for_html      # trim, escape HTML entities
sanitizer = Amber::Schema::Parser::Sanitizer.for_email     # trim, lowercase
sanitizer = Amber::Schema::Parser::Sanitizer.for_username  # trim, lowercase, remove non-printable

# Custom combination
sanitizer = Amber::Schema::Parser::Sanitizer.new([
  Amber::Schema::Parser::Sanitizer::Option::TrimWhitespace,
  Amber::Schema::Parser::Sanitizer::Option::NormalizeWhitespace,
  Amber::Schema::Parser::Sanitizer::Option::EscapeHTML,
])

cleaned = sanitizer.parse(JSON::Any.new("  <b>hello</b>  world  "))
```

Available options: `TrimWhitespace`, `RemoveHTML`, `EscapeHTML`, `Lowercase`, `Uppercase`, `RemoveNonPrintable`, `NormalizeWhitespace`.

## Result Types

The Schema API provides both a legacy `LegacyResult` and a typed functional `Result` system.

### LegacyResult

Returned by `Definition#validate` and `RequestSchema#parse`:

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
result.to_typed_result   # => Success(...) | Failure(...)
```

### Typed Result (Success / Failure)

Returned by `Definition#validate_typed`:

```crystal
result = schema.validate_typed

case result
when Amber::Schema::Success
  result.value  # => Hash(String, JSON::Any)
when Amber::Schema::Failure
  result.error  # => ValidationFailure
  result.error.messages           # => Array(String)
  result.error.errors_by_field    # => Hash(String, Array(Error))
  result.error.has_error_for_field?("email")  # => Bool
  result.error.errors_for_field("email")      # => Array(Error)
end
```

Supports monadic operations:

```crystal
result
  .map { |data| transform(data) }
  .flat_map { |data| another_validation(data) }
  .on_success { |data| log_success(data) }
  .on_failure { |error| log_error(error) }
```

Recovery from failure:

```crystal
result.or_else { |error| provide_default_value }
```

Factory methods via the `Result(T)` module:

```crystal
Amber::Schema::Result(Hash(String, JSON::Any)).success(data)
Amber::Schema::Result(Hash(String, JSON::Any)).failure(validation_failure)
```

### ResultHelpers

Utilities for combining multiple results:

```crystal
# First success from multiple attempts
Amber::Schema::ResultHelpers.first_success([result_a, result_b])

# All must succeed; collects all errors if any fail
Amber::Schema::ResultHelpers.combine([result_a, result_b, result_c])

# Combine a hash of results into a result of hash
Amber::Schema::ResultHelpers.sequence({"user" => result_a, "order" => result_b})
```

## Error Types and Formatting

### Error Classes

All errors extend `Amber::Schema::Error` which provides `field`, `message`, `code`, `details`, and `to_h`.

| Error Class | Code | When Raised |
|---|---|---|
| `RequiredFieldError` | `required_field_missing` | Required field absent |
| `TypeMismatchError` | `type_mismatch` | Value cannot be coerced to declared type. Details: `{expected, actual}` |
| `InvalidFormatError` | `invalid_format` | String fails format validation. Details: `{format, value}` |
| `RangeError` | `out_of_range` | Numeric value outside min/max bounds. Details: `{min?, max?, value?}` |
| `LengthError` | `invalid_length` | String/array length outside bounds. Details: `{min_length?, max_length?, actual_length?}` |
| `CustomValidationError` | configurable | Custom validator failures |
| `ValidationError` | `validation_failed` | General validation error |

Setup errors: `SchemaDefinitionError`, `InvalidSchemaError`, `DuplicateFieldError`.

`Warning` is a non-fatal variant with `field`, `message`, and `code`.

### ErrorFormatter

Controls how errors are serialized:

```crystal
formatter = Amber::Schema::ResponseFormatters::ErrorFormatter.new(
  group_by: Amber::Schema::ResponseFormatters::ErrorFormatter::GroupBy::Field,
  detail_level: Amber::Schema::ResponseFormatters::ErrorFormatter::DetailLevel::Standard
)

formatted = formatter.format(errors)  # => JSON::Any
```

Grouping options: `Field`, `Code`, `None` (flat list). Detail levels: `Minimal` (message only), `Standard` (field + message + code), `Full` (all details including metadata).

Static helpers:

```crystal
Amber::Schema::ResponseFormatters::ErrorFormatter.summarize(errors)        # => "3 validation errors in 2 fields"
Amber::Schema::ResponseFormatters::ErrorFormatter.detailed_report(errors)  # => multi-line debug string
Amber::Schema::ResponseFormatters::ErrorFormatter.to_html(errors)          # => HTML <ul> for error pages
```

### JSONResponse Formatter

Produces complete HTTP JSON responses in multiple structures:

```crystal
formatter = Amber::Schema::ResponseFormatters::JSONResponse.new(
  structure: Amber::Schema::ResponseFormatters::JSONResponse::Structure::Envelope,
  pretty: false,
  include_metadata: true
)

# From a ResponseBuilder
json_string = formatter.format(builder)

# Standard error responses
formatter.bad_request("Invalid input")
formatter.not_found("User not found")
formatter.unprocessable_entity(errors)
formatter.unauthorized
formatter.forbidden
formatter.internal_server_error
formatter.error_response(status_code, message, code)
```

Structure options:

- `Simple` -- data hash on success, `{errors: [...]}` on failure
- `Envelope` -- wrapped with `status`, `success`, `data`, `errors`, `warnings`, `meta`, `timestamp`
- `JSONAPI` -- JSON:API 1.0 format with `jsonapi.version`, `data`, `errors` (with `source.pointer`, `title`, `detail`), `meta`

### ResponseBuilder

Programmatic response construction with method chaining:

```crystal
builder = Amber::Schema::ResponseBuilder.success(data)
builder.add_metadata("request_id", JSON::Any.new("abc-123"))
builder.paginate(page: 1, per_page: 20, total: 100)

json_string = builder.to_json
http_status = builder.http_status  # => 200 (success), 206 (partial), 422/400 (error)

builder = Amber::Schema::ResponseBuilder.from_result(legacy_result)
```

Factory methods: `ResponseBuilder.success`, `ResponseBuilder.error`, `ResponseBuilder.validation_error`, `ResponseBuilder.not_found`, `ResponseBuilder.unauthorized`, `ResponseBuilder.forbidden`.

## Controller Integration

The `Amber::Controller::SchemaIntegration` module is automatically included in `Amber::Controller::Base`. It provides schema validation in the request lifecycle.

### Validating Requests

```crystal
class UsersController < Amber::Controller::Base
  validate_schema :create

  def create
    data = request_data.not_nil!
    email = data["email"].as_s
    respond_with({"id" => JSON::Any.new(1_i64)}, status: 201)
  end
end
```

When `validate_schema` is used and validation fails, the controller automatically returns a 422 response with structured JSON errors via `JSONResponse#unprocessable_entity`. The validated data is stored in `@request_data`.

### Accessing Data

```crystal
# Validated data from schema (Hash(String, JSON::Any)?)
request_data

# Alias for request_data
validated_params

# Check if validation failed
validation_failed?

# Full validation result
@validation_result  # => Amber::Schema::LegacyResult?

# Raw HTTP params (Amber::Router::Params)
raw_params

# Legacy params with old Amber::Validators interface
legacy_params
```

### Response Helpers

```crystal
# JSON response with status code
respond_with(data_hash, status: 200)

# Alias for respond_with
render_validated(data_hash, status: 200)

# Error responses
respond_with_error("Something went wrong", status: 400, code: "bad_request")
respond_with_errors(schema.errors, status: 422)
```

### Request Data Merging

The `merge_request_data` private method combines data from all sources in order:

1. Route path parameters (from `request.route.params`)
2. Query parameters (from `request.query_params`)
3. Parsed body data (JSON by default, based on Content-Type)

Later sources override earlier ones for duplicate keys.

### SchemaParamsWrapper

When schema validation runs, `params` returns a `SchemaParamsWrapper` instead of the legacy `Amber::Validators::Params`. The wrapper:

- Checks validated schema data first for any key lookup
- Falls back to raw `Amber::Router::Params` for unvalidated fields
- Converts `JSON::Any` values to strings for backward compatibility with `params[:key]`
- Provides `to_h` (merged hash), `to_unsafe_h` (raw params only), `has_key?`, and `validation` for legacy code
- Forwards unknown methods to raw params via `forward_missing_to`

```crystal
# Works the same whether schema is active or not
params["email"]          # => String from validated data or raw params
params["email"]?         # => String? (nil-safe)
params.has_key?("email") # checks both sources

# Access legacy validation interface during migration
params.validation do
  required(:email) { |p| p.email? }
end
```

### Annotations

Annotations on controller methods document request/response contracts:

```crystal
class UsersController < Amber::Controller::Base
  @[Amber::Schema::Request(schema: CreateUserSchema, content_type: "application/json")]
  @[Amber::Schema::Response(status: 201, schema: UserSchema, description: "User created")]
  @[Amber::Schema::PathParam(name: "id", type: Int32, description: "User ID")]
  @[Amber::Schema::QueryParam(name: "include", type: String, required: false, default: "")]
  @[Amber::Schema::Header(name: "X-API-Key", type: String, required: true)]
  @[Amber::Schema::Tag(name: "Users", description: "User management")]
  @[Amber::Schema::Summary("Create a new user")]
  @[Amber::Schema::Security(scheme: "bearer")]
  @[Amber::Schema::OperationId("createUser")]
  @[Amber::Schema::Deprecated(reason: "Use v2", since: "1.5.0")]
  @[Amber::Schema::RateLimit(limit: 100, window: 3600)]
  def create
    # ...
  end
end
```

## Migration from Amber::Validators

### Before (old params validation)

```crystal
class UsersController < Amber::Controller::Base
  def create
    validation = params.validation do
      required(:email) { |p| p.email? }
      required(:password) { |p| p.size >= 8 }
      optional(:name)
    end

    unless validation.valid?
      response.status_code = 400
      response.print({errors: validation.errors}.to_json)
      return
    end

    email = params[:email]       # always String
    password = params[:password]  # always String
  end
end
```

### After (Schema API)

```crystal
class CreateUserSchema < Amber::Schema::Definition
  field email, String, required: true, format: "email"
  field password, String, required: true, min_length: 8
  field name, String
end

class UsersController < Amber::Controller::Base
  validate_schema :create

  def create
    data = request_data.not_nil!
    email = data["email"].as_s        # String, already validated
    password = data["password"].as_s   # String, guaranteed >= 8 chars
    name = data["name"]?.try(&.as_s)   # String? optional
  end
end
```

### Key differences

1. Validation moves from inside actions to class-level schema definitions
2. `params[:key]` (always String) becomes `request_data["key"]` (`JSON::Any` with real types)
3. Manual error responses become automatic 422 with structured JSON
4. Type coercion is automatic -- `"42"` from a form becomes `Int32` when declared
5. Existing code continues to work: `params` returns a `SchemaParamsWrapper` that bridges both systems

### Gradual migration path

- Existing controllers work without changes
- Use `legacy_params` for explicit access to the old `Amber::Validators::Params` interface
- Use `raw_params` for direct `Amber::Router::Params` access
- Start new actions with `validate_schema`; migrate old ones when convenient

## Key Source Files

| File | Purpose |
|---|---|
| `src/amber/schema.cr` | Entry point, requires all components |
| `src/amber/schema/definition.cr` | Base `Definition` class, `field` macro, validation engine |
| `src/amber/schema/request_schema.cr` | `RequestSchema` with parse + validate |
| `src/amber/schema/response_schema.cr` | `ResponseSchema` with lenient validation, strip options |
| `src/amber/schema/result.cr` | `Success`, `Failure`, `LegacyResult`, `ValidationFailure`, `ResultHelpers` |
| `src/amber/schema/errors.cr` | All error classes and `Warning` |
| `src/amber/schema/type_coercion.cr` | `TypeCoercion` module with coercion registry |
| `src/amber/schema/validator.cr` | `Validator::Base`, `Context`, `Custom`, `Composite`, `Conditional` |
| `src/amber/schema/validators/required.cr` | `Validator::Required` |
| `src/amber/schema/validators/length.cr` | `Validator::Length`, `MinLength`, `MaxLength` |
| `src/amber/schema/validators/format.cr` | `Validator::Format` with `FormatType` enum and built-in patterns |
| `src/amber/schema/validators/range.cr` | `Validator::Range`, `Min`, `Max` |
| `src/amber/schema/validators/pattern.cr` | `Validator::Pattern` (regex) |
| `src/amber/schema/validators/enum.cr` | `Validator::Enum` |
| `src/amber/schema/validators/type.cr` | `Validator::Type` |
| `src/amber/schema/parser.cr` | `Parser::Base`, `ParserRegistry`, `TypeCoercion` parser, `Transform`, `Chain` |
| `src/amber/schema/parsers/json_parser.cr` | `JSONParser` with nested key and aliasing support |
| `src/amber/schema/parsers/query_parser.cr` | `QueryParser` for URL-encoded and query string data |
| `src/amber/schema/parsers/multipart_parser.cr` | `MultipartParser` and `FileUploadValidator` |
| `src/amber/schema/parsers/xml_parser.cr` | `XMLParser` with `XPathContext` |
| `src/amber/schema/parsers/sanitizer.cr` | `Sanitizer` with preset profiles |
| `src/amber/schema/response/error_formatter.cr` | `ErrorFormatter` with grouping and detail levels |
| `src/amber/schema/response/json_response.cr` | `JSONResponse` formatter (Envelope, Simple, JSONAPI) |
| `src/amber/schema/response_builder.cr` | `ResponseBuilder` with factory methods and pagination |
| `src/amber/schema/annotations.cr` | All annotation definitions for schemas and OpenAPI |
| `src/amber/schema/dsl.cr` | Shorthand DSL macros (`string`, `integer`, `boolean`, etc.) |
| `src/amber/schema/controller_integration_simple.cr` | `ControllerIntegration` mixin for controllers |
| `src/amber/controller/schema_integration.cr` | `SchemaIntegration`, `SchemaParamsWrapper`, Base patch |
| `src/amber/schema/migration_guide.cr` | Detailed migration examples and patterns |

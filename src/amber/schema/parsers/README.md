# Amber Schema JSON Parser

## Overview

The JSON parser is a production-ready parser for the Amber Schema system that handles JSON request bodies, form data, and multipart uploads.

## Features

### 1. JSON Parsing
- Parses raw JSON strings into `Hash(String, JSON::Any)`
- Handles nested objects and arrays
- Wraps root arrays in a `data` key for consistency
- Wraps primitive values in a `value` key

### 2. Form Data Parsing
- Parses `HTTP::Params` into nested JSON structures
- Supports bracket notation: `user[name]=John`
- Supports array notation: `tags[]=ruby&tags[]=crystal`
- Automatic type coercion for numbers, booleans, and null values

### 3. Type Coercion
- Strings: `"true"` → `true`, `"123"` → `123`, `"3.14"` → `3.14`
- Booleans: `"true"`, `"false"`, `"1"`, `"0"`, `"yes"`, `"no"`
- Numbers: Integer and float parsing with scientific notation support
- Null: `"null"` → `nil`, empty strings → `nil`
- Embedded JSON: Parses JSON strings in query parameters

### 4. Content-Type Based Selection
- Automatic parser selection via `ParserRegistry`
- Supports:
  - `application/json`
  - `text/json`
  - `application/x-www-form-urlencoded`
  - `multipart/form-data`

### 5. Error Handling
- Detailed error messages for JSON parse failures
- Graceful handling of malformed data
- Type safety with Crystal's type system

## Usage

### Basic JSON Parsing

```crystal
json_string = %({"name": "John", "age": 30})
data = Amber::Schema::Parser::JSONParser.parse_string(json_string)
# => {"name" => JSON::Any("John"), "age" => JSON::Any(30)}
```

### Form Data Parsing

```crystal
params = HTTP::Params.parse("user[name]=John&user[age]=30&tags[]=ruby")
data = Amber::Schema::Parser::JSONParser.parse_params(params)
# => {"user" => {"name" => "John", "age" => 30}, "tags" => ["ruby"]}
```

### With Schema Validation

```crystal
class UserSchema < Amber::Schema::Definition
  field :name, String, required: true
  field :email, String, required: true, format: "email"
  field :age, Int32, min: 18
end

data = Amber::Schema::Parser::JSONParser.parse_string(json)
schema = UserSchema.new(data)
result = schema.validate

if result.success?
  puts schema.name  # Typed access to fields
else
  result.errors.each do |error|
    puts "#{error.field}: #{error.message}"
  end
end
```

### Controller Integration

```crystal
class UsersController < ApplicationController
  include Amber::Schema::ControllerIntegration

  def create
    # Automatically parses based on Content-Type
    data = parse_request_data
    schema = UserSchema.new(data)
    
    if result = schema.validate
      # Process valid data
    else
      # Handle validation errors
    end
  end
end
```

## Limitations

Current limitations that need to be addressed:

1. **Array Index Notation**: Parameters like `items[0][name]=First` are not yet fully supported
2. **Generic Types**: Array(T) and Hash(K,V) field types need additional work
3. **File Uploads**: Basic structure is in place but needs testing
4. **Field Aliasing**: The `as:` option for field aliasing needs refinement

## Parser Registry

The parser system uses a registry pattern for content-type based selection:

```crystal
# Register custom parser
ParserRegistry.register("application/xml", XMLParser)

# Parse request automatically selects parser
data = ParserRegistry.parse_request(request)
```

## Edge Cases Handled

1. **Empty Bodies**: Returns empty hash
2. **Invalid JSON**: Raises `SchemaDefinitionError` with details
3. **Mixed Content**: Attempts JSON parsing for ambiguous content
4. **Unicode**: Full support for UTF-8 characters
5. **Large Numbers**: Handles scientific notation
6. **Deep Nesting**: No artificial depth limits
# Amber Schema API Demo

This example application demonstrates the comprehensive features of the Amber Schema API, including request validation, response formatting, nested object validation, custom validators, and migration from traditional parameter handling.

## Overview

The demo application is a user management API that showcases:

- **Basic CRUD operations** with schema validation
- **Query parameter validation** for search and filtering
- **Path parameter validation** in RESTful routes
- **Nested object validation** for addresses and preferences
- **Custom validators** for business logic
- **Error handling** with consistent error responses
- **Content type handling** for JSON and form data
- **Bulk operations** with array validation
- **Conditional validation** based on field values
- **File upload validation** (simulated)
- **Export/Import** functionality with format validation

## Project Structure

```
schema_api_demo/
├── config/
│   └── routes.cr              # Route definitions
├── src/
│   ├── controllers/
│   │   └── users_controller.cr # Controllers with schema integration
│   ├── schemas/
│   │   └── user_schemas.cr    # Schema definitions
│   └── models/
│       └── user.cr            # Simple user model
└── README.md                  # This file
```

## Running the Demo

To run this demo within the Amber framework:

```crystal
# From the amber root directory
require "./examples/schema_api_demo/src/models/user"
require "./examples/schema_api_demo/src/schemas/user_schemas"
require "./examples/schema_api_demo/src/controllers/users_controller"
require "./examples/schema_api_demo/config/routes"

# Start the server
Amber::Server.start
```

## API Endpoints

### User Management

#### List Users
```bash
GET /users?q=john&role=admin&is_active=true&page=1&per_page=20&sort_by=created_at&sort_order=desc

# Query parameters are validated:
# - q: search query (max 100 chars)
# - role: enum of [user, moderator, admin]
# - is_active: boolean
# - tags: array of strings
# - page: integer >= 1
# - per_page: integer between 1-100
# - sort_by: enum of [created_at, updated_at, email, username]
# - sort_order: enum of [asc, desc]
```

#### Get Single User
```bash
GET /users/1
```

#### Create User
```bash
POST /users
Content-Type: application/json

{
  "email": "john.doe@example.com",
  "first_name": "John",
  "last_name": "Doe",
  "username": "johndoe",
  "password": "securepass123",
  "password_confirmation": "securepass123",
  "age": 30,
  "phone": "+1234567890",
  "role": "user",
  "tags": ["vip", "beta-tester"],
  "address": {
    "street": "123 Main Street",
    "city": "San Francisco",
    "state": "CA",
    "postal_code": "94105",
    "country": "US"
  },
  "preferences": {
    "theme": "dark",
    "notifications_enabled": true,
    "language": "en",
    "timezone": "America/Los_Angeles"
  }
}
```

#### Update User
```bash
PATCH /users/1
Content-Type: application/json

{
  "email": "new.email@example.com",
  "tags": ["updated", "premium"]
}
```

#### Delete User
```bash
DELETE /users/1
```

### User Actions

#### Activate User
```bash
POST /users/1/activate
Content-Type: application/json

{
  "reason": "Email verified",
  "notify_user": true,
  "email_template": "activation",
  "custom_message": "Welcome to our platform!"
}
```

#### Deactivate User
```bash
POST /users/1/deactivate
Content-Type: application/json

{
  "reason": "Account suspended for review",
  "notify_user": false
}
```

### Bulk Operations

#### Bulk Create Users
```bash
POST /users/bulk
Content-Type: application/json

{
  "users": [
    {
      "email": "user1@example.com",
      "first_name": "User",
      "last_name": "One",
      "username": "user1",
      "password": "password123",
      "password_confirmation": "password123"
    },
    {
      "email": "user2@example.com",
      "first_name": "User",
      "last_name": "Two",
      "username": "user2",
      "password": "password123",
      "password_confirmation": "password123"
    }
  ]
}
```

#### Bulk Delete Users
```bash
DELETE /users/bulk
Content-Type: application/json

{
  "ids": [1, 2, 3],
  "confirm": true
}
```

### Import/Export

#### Export Users
```bash
GET /users/export?format=csv&fields=id,email,username,created_at&include_inactive=false&date_from=2024-01-01&date_to=2024-12-31
```

#### Import Users
```bash
POST /users/import
Content-Type: application/json

{
  "file": "base64_encoded_file_content",
  "format": "csv",
  "skip_errors": true,
  "dry_run": false
}
```

### Authentication

#### Login
```bash
POST /auth/login
Content-Type: application/json

{
  "username_or_email": "johndoe",
  "password": "password123",
  "remember_me": true,
  "device_id": "device-123",
  "device_name": "John's iPhone"
}
```

## Schema Features Demonstrated

### 1. Field Types and Basic Validation

```crystal
field :email, String, required: true, format: "email"
field :age, Int32, min: 13, max: 120
field :tags, Array(String), max_length: 10
```

### 2. Nested Object Validation

```crystal
nested :address, AddressSchema
nested :preferences, UserPreferencesSchema
```

### 3. Custom Validators

```crystal
validate do |context|
  password = context.data["password"]?.try(&.as_s)
  confirmation = context.data["password_confirmation"]?.try(&.as_s)
  
  if password && confirmation && password != confirmation
    context.add_error(Amber::Schema::CustomValidationError.new(
      "password_confirmation",
      "Password confirmation does not match",
      "passwords_mismatch"
    ))
  end
end
```

### 4. Conditional Validation

```crystal
when_field :notify_user, true do
  field :email_template, String, required: true, enum: ["activation", "deactivation", "custom"]
  field :custom_message, String, max_length: 1000
end
```

### 5. Parameter Source Configuration

```crystal
from_query do
  field :q, String, max_length: 100
  field :page, Int32, min: 1, default: 1
end

from_path do
  field :id, Int64, required: true
end

from_body do
  field :email, String, required: true
end
```

### 6. Format Validation

The schema API supports various format validations:
- `email`: RFC-compliant email addresses
- `url`/`uri`: Valid URLs
- `uuid`: Valid UUIDs
- `iso8601`/`datetime`: ISO8601 datetime strings
- `date`: YYYY-MM-DD format
- `ipv4`/`ipv6`: IP addresses
- `hostname`: Valid hostnames
- Custom regex patterns

### 7. Enum Validation

```crystal
field :role, String, enum: ["user", "moderator", "admin"]
field :theme, String, enum: ["light", "dark", "auto"], default: "light"
```

### 8. Array Validation

```crystal
field :tags, Array(String), max_length: 10
field :interests, Array(String), enum: ["tech", "business", "design", "marketing"]
```

## Error Handling

The schema API provides consistent error responses:

```json
{
  "errors": [
    {
      "field": "email",
      "message": "Email is already taken",
      "code": "email_taken"
    },
    {
      "field": "age",
      "message": "Must be at least 13",
      "code": "below_minimum"
    }
  ]
}
```

## Migration from Traditional Params

### Before (Traditional Approach)

```crystal
def create
  email = params[:email]?
  if email.nil? || email.empty?
    return render_error("Email is required")
  end
  
  unless email.matches?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
    return render_error("Invalid email format")
  end
  
  age = params[:age]?.try(&.to_i)
  if age && (age < 13 || age > 120)
    return render_error("Age must be between 13 and 120")
  end
  
  # More manual validation...
end
```

### After (Schema API Approach)

```crystal
def create
  create_schema = Schemas::CreateUserSchema.new(request_body_hash)
  result = create_schema.validate
  
  if result.failure?
    return respond_with_errors(result.errors, 422)
  end
  
  # All validation is handled by the schema
  user = Models::User.create(result.data.not_nil!)
  respond_with({"user" => user.to_h}, 201)
end
```

## Best Practices

1. **Organize Schemas**: Group related schemas in modules for better organization
2. **Reuse Common Schemas**: Create base schemas for common patterns (addresses, phone numbers, etc.)
3. **Use Appropriate Validators**: Choose the right validator for each use case
4. **Provide Clear Error Messages**: Help API consumers understand what went wrong
5. **Document Schemas**: Use schema definitions as API documentation
6. **Test Schemas**: Write tests for complex validation logic
7. **Version Schemas**: Consider versioning schemas for API evolution

## Advanced Features

### Type Coercion

The schema API automatically coerces compatible types:
- String "123" → Int32 123
- String "true" → Bool true
- String "2024-01-01T00:00:00Z" → Time object

### Custom Format Validators

You can define custom format validators:

```crystal
field :phone, String, format: "^\\+?[1-9]\\d{1,14}$"  # E.164 format
```

### Nested Array Validation

Validate arrays of complex objects:

```crystal
field :users, Array(Hash(String, JSON::Any)), required: true, min_length: 1, max_length: 100

validate do |context|
  # Validate each user in the array
end
```

### Dynamic Conditional Validation

Use `when_present` for dynamic requirements:

```crystal
when_present :address do
  field :postal_code, String, required: true
  field :country, String, required: true
end
```

## Testing Schemas

Example of testing a schema:

```crystal
describe Schemas::CreateUserSchema do
  it "validates required fields" do
    schema = Schemas::CreateUserSchema.new({} of String => JSON::Any)
    result = schema.validate
    
    result.failure?.should be_true
    result.errors.map(&.field).should contain("email")
    result.errors.map(&.field).should contain("first_name")
  end
  
  it "validates email format" do
    data = {
      "email" => JSON::Any.new("invalid-email"),
      # ... other required fields
    }
    
    schema = Schemas::CreateUserSchema.new(data)
    result = schema.validate
    
    result.failure?.should be_true
    result.errors.find { |e| e.field == "email" && e.code == "invalid_format" }.should_not be_nil
  end
end
```

## Conclusion

The Amber Schema API provides a powerful, declarative way to handle request validation and response formatting. It reduces boilerplate code, improves consistency, and makes your API more maintainable and self-documenting.

For more information, see the main Amber documentation on the Schema API.
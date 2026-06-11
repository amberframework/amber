# Crystal annotations for schema validation and API documentation
# These annotations support both validation rules and OpenAPI documentation
module Amber::Schema
  # Schema Validation Annotations
  # =============================

  # Mark a property as required in the schema
  # Example: @[Required]
  annotation Required
  end

  # Define the expected type for a field
  # Example: @[Type(String)]
  annotation Type
  end

  # Specify a default value for a field
  # Example: @[Default("pending")]
  annotation Default
  end

  # Add a description to a field for documentation
  # Example: @[Description("User's email address")]
  annotation Description
  end

  # Validate string format (email, url, uuid, etc.)
  # Example: @[Format("email")]
  annotation Format
  end

  # Define minimum value/length constraints
  # Example: @[Min(8)]
  annotation Min
  end

  # Define maximum value/length constraints
  # Example: @[Max(128)]
  annotation Max
  end

  # Define a regex pattern for string validation
  # Example: @[Pattern(/^(?=.*[A-Za-z])(?=.*\d).+$/)]
  annotation Pattern
  end

  # Mark a field as allowing null values
  # Example: @[Nullable]
  annotation Nullable
  end

  # Define allowed values (enum)
  # Example: @[Enum(["active", "inactive", "pending"])]
  annotation Enum
  end

  # Custom validation message
  # Example: @[Message("Password must contain at least one letter and one number")]
  annotation Message
  end

  # Group related fields together
  # Example: @[Group("authentication")]
  annotation Group
  end

  # Conditional validation based on other fields
  # Example: @[When("role", "admin")]
  annotation When
  end

  # Transform the value after validation
  # Example: @[Transform("downcase")]
  annotation Transform
  end

  # API Documentation Annotations
  # =============================

  # Define request schema and content type for an endpoint
  # Properties:
  # - schema: The schema class to use for request validation
  # - content_type: The expected content type (default: "application/json")
  # Example: @[Request(schema: CreateUserSchema, content_type: "application/json")]
  annotation Request
  end

  # Define response schema, status code, and description for an endpoint
  # Properties:
  # - status: HTTP status code (e.g., 200, 201, 404)
  # - schema: The schema class for the response body (optional)
  # - description: Human-readable description of the response
  # - content_type: The response content type (default: "application/json")
  # Example: @[Response(status: 200, schema: UserSchema, description: "User retrieved successfully")]
  annotation Response
  end

  # Define a query parameter for an endpoint
  # Properties:
  # - name: Parameter name
  # - type: Parameter type (e.g., String, Int32, Bool)
  # - required: Whether the parameter is required (default: false)
  # - description: Human-readable description
  # - default: Default value if not provided
  # - enum: Array of allowed values
  # Example: @[QueryParam(name: "page", type: Int32, required: false, description: "Page number", default: 1)]
  annotation QueryParam
  end

  # Define a path parameter for an endpoint
  # Properties:
  # - name: Parameter name (must match route parameter)
  # - type: Parameter type (e.g., String, Int32, UUID)
  # - description: Human-readable description
  # - format: Optional format specification (e.g., "uuid", "email")
  # Example: @[PathParam(name: "id", type: Int32, description: "User ID")]
  annotation PathParam
  end

  # Define a header parameter for an endpoint
  # Properties:
  # - name: Header name
  # - type: Header value type (usually String)
  # - required: Whether the header is required (default: false)
  # - description: Human-readable description
  # - default: Default value if not provided
  # Example: @[Header(name: "X-API-Key", type: String, required: true, description: "API authentication key")]
  annotation Header
  end

  # Add OpenAPI tags to group endpoints
  # Properties:
  # - name: Tag name
  # - description: Optional tag description
  # Example: @[Tag(name: "Users", description: "User management endpoints")]
  annotation Tag
  end

  # Add a summary to an endpoint for API documentation
  # Properties:
  # - value: Short summary of what the endpoint does
  # Example: @[Summary("Create a new user")]
  annotation Summary
  end

  # Add a detailed description to an endpoint
  # Properties:
  # - value: Detailed description of the endpoint's behavior
  # Example: @[Description("Creates a new user account with the provided information. Returns the created user.")]
  annotation Description
  end

  # Define security requirements for an endpoint
  # Properties:
  # - scheme: Security scheme name (e.g., "bearer", "api_key", "oauth2")
  # - scopes: Array of required scopes (for OAuth2)
  # Example: @[Security(scheme: "bearer")]
  # Example: @[Security(scheme: "oauth2", scopes: ["read:users", "write:users"])]
  annotation Security
  end

  # Additional API Documentation Annotations
  # ========================================

  # Mark an endpoint as deprecated
  # Properties:
  # - reason: Optional reason for deprecation
  # - since: Optional version when deprecated
  # Example: @[Deprecated(reason: "Use v2 endpoint instead", since: "1.5.0")]
  annotation Deprecated
  end

  # Define operation ID for OpenAPI specification
  # Properties:
  # - value: Unique operation identifier
  # Example: @[OperationId("createUser")]
  annotation OperationId
  end

  # Specify external documentation
  # Properties:
  # - url: URL to external documentation
  # - description: Optional description of the external docs
  # Example: @[ExternalDocs(url: "https://docs.example.com/users", description: "User API guide")]
  annotation ExternalDocs
  end

  # Define request body examples
  # Properties:
  # - name: Example name
  # - value: Example value (as a hash or string)
  # - description: Optional description
  # Example: @[Example(name: "valid_user", value: {name: "John", email: "john@example.com"})]
  annotation Example
  end

  # Specify rate limiting for an endpoint
  # Properties:
  # - limit: Number of requests allowed
  # - window: Time window in seconds
  # Example: @[RateLimit(limit: 100, window: 3600)]
  annotation RateLimit
  end

  # Define accepted media types for file uploads
  # Properties:
  # - types: Array of accepted MIME types
  # Example: @[Accept(types: ["image/jpeg", "image/png", "image/gif"])]
  annotation Accept
  end

  # Mark endpoint as requiring specific permissions
  # Properties:
  # - permissions: Array of required permissions
  # Example: @[RequirePermissions(permissions: ["users.create", "users.update"])]
  annotation RequirePermissions
  end
end

# Error types and definitions for the Schema API
module Amber::Schema
  # Base error class for all schema-related errors
  class Error < Exception
    getter field : String
    getter code : String
    getter details : Hash(String, JSON::Any)?

    def initialize(@field : String, @message : String, @code : String, @details : Hash(String, JSON::Any)? = nil)
      super(@message)
    end

    def to_h
      hash = {} of String => JSON::Any
      hash["field"] = JSON::Any.new(@field)
      hash["message"] = JSON::Any.new(@message || "")
      hash["code"] = JSON::Any.new(@code)
      if details = @details
        hash["details"] = JSON::Any.new(details)
      end
      hash
    end
  end

  # Specific error types
  class ValidationError < Error
    def initialize(field : String, message : String, details : Hash(String, JSON::Any)? = nil)
      super(field, message, "validation_failed", details)
    end
  end

  class RequiredFieldError < Error
    def initialize(field : String)
      super(field, "Field '#{field}' is required", "required_field_missing")
    end
  end

  class TypeMismatchError < Error
    def initialize(field : String, expected_type : String, actual_type : String)
      super(
        field,
        "Field '#{field}' must be of type #{expected_type}, got #{actual_type}",
        "type_mismatch",
        {"expected" => JSON::Any.new(expected_type), "actual" => JSON::Any.new(actual_type)} of String => JSON::Any
      )
    end
  end

  class InvalidFormatError < Error
    def initialize(field : String, format : String, value : String)
      super(
        field,
        "Field '#{field}' has invalid format. Expected #{format}",
        "invalid_format",
        {"format" => JSON::Any.new(format), "value" => JSON::Any.new(value)} of String => JSON::Any
      )
    end
  end

  class RangeError < Error
    def initialize(field : String, min : Float64? = nil, max : Float64? = nil, value : Float64? = nil)
      message = "Field '#{field}' is out of range"
      details = {} of String => JSON::Any

      if min && max
        message = "Field '#{field}' must be between #{min} and #{max}"
        details["min"] = JSON::Any.new(min)
        details["max"] = JSON::Any.new(max)
      elsif min
        message = "Field '#{field}' must be at least #{min}"
        details["min"] = JSON::Any.new(min)
      elsif max
        message = "Field '#{field}' must be at most #{max}"
        details["max"] = JSON::Any.new(max)
      end

      details["value"] = JSON::Any.new(value) if value

      super(field, message, "out_of_range", details)
    end
  end

  class LengthError < Error
    def initialize(field : String, min : Int32? = nil, max : Int32? = nil, actual : Int32? = nil)
      message = "Field '#{field}' has invalid length"
      details = {} of String => JSON::Any

      if min && max
        message = "Field '#{field}' length must be between #{min} and #{max} characters"
        details["min_length"] = JSON::Any.new(min)
        details["max_length"] = JSON::Any.new(max)
      elsif min
        message = "Field '#{field}' must be at least #{min} characters"
        details["min_length"] = JSON::Any.new(min)
      elsif max
        message = "Field '#{field}' must be at most #{max} characters"
        details["max_length"] = JSON::Any.new(max)
      end

      details["actual_length"] = JSON::Any.new(actual) if actual

      super(field, message, "invalid_length", details)
    end
  end

  class CustomValidationError < Error
    def initialize(field : String, message : String, code : String = "custom_validation_failed")
      super(field, message, code)
    end
  end

  # Schema definition errors (compile-time/setup errors)
  class SchemaDefinitionError < Exception
    def initialize(message : String)
      super("Schema definition error: #{message}")
    end
  end

  class InvalidSchemaError < SchemaDefinitionError
  end

  class DuplicateFieldError < SchemaDefinitionError
    def initialize(field_name : String)
      super("Field '#{field_name}' is already defined in this schema")
    end
  end

  # Warning class for non-critical validation issues
  class Warning
    getter field : String
    getter message : String
    getter code : String

    def initialize(@field : String, @message : String, @code : String = "warning")
    end

    def to_h
      {
        "field"   => JSON::Any.new(@field),
        "message" => JSON::Any.new(@message),
        "code"    => JSON::Any.new(@code),
        "type"    => JSON::Any.new("warning"),
      } of String => JSON::Any
    end
  end
end

# Concrete implementation for response validation schemas
module Amber::Schema
  class ResponseSchema < Definition
    # Additional response-specific options
    getter strip_null_values : Bool
    getter strip_empty_arrays : Bool

    def initialize(
      name : String,
      description : String? = nil,
      version : String? = nil,
      @strip_null_values : Bool = false,
      @strip_empty_arrays : Bool = false,
    )
      super(name, description, version)
    end

    def validate(data : Hash(String, JSON::Any)) : LegacyResult
      result = LegacyResult.new(true, data, data)
      context = Validator::Context.new(data, result, self)

      # For responses, we're more lenient - only validate present fields
      @fields.each do |field_name, field_def|
        if data.has_key?(field_name)
          # Type validation
          type_validator = Validator::Type.new(field_name, field_def.type)
          type_validator.validate(context)

          # Field-specific validators
          field_def.validators.each do |validator|
            validator.validate(context)
          end
        elsif field_def.required
          # Required fields must be present in responses
          validator = Validator::Required.new(field_name)
          validator.validate(context)
        end
      end

      # Run custom validators
      @validators.each do |validator|
        validator.validate(context)
      end

      result
    end

    def parse(data : Hash(String, JSON::Any)) : LegacyResult
      # First validate
      validation_result = validate(data)
      return validation_result if validation_result.failure?

      # Then clean/transform
      cleaned_data = {} of String => JSON::Any

      data.each do |key, value|
        # Skip null values if configured
        next if @strip_null_values && value.raw.nil?

        # Skip empty arrays if configured
        if @strip_empty_arrays && value.as_a? && value.as_a.empty?
          next
        end

        # Include defined fields
        if field_def = @fields[key]?
          # Apply any field transformations
          parser = Parser::TypeCoercion.new(field_def.type)
          cleaned_data[key] = parser.parse(value)
        else
          # Include unknown fields with a warning
          cleaned_data[key] = value
          validation_result.add_warning(
            Warning.new(key, "Unknown field '#{key}' in response", "unknown_field")
          )
        end
      end

      # Add default values for missing optional fields
      @fields.each do |field_name, field_def|
        if !cleaned_data.has_key?(field_name) && field_def.default_value
          cleaned_data[field_name] = JSON::Any.new(field_def.default_value)
        end
      end

      LegacyResult.success(cleaned_data)
    end

    # Helper to ensure response conforms to schema
    def conform(data : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
      result = parse(data)
      if result.success? && result.data
        result.data
      else
        # Return original data if parsing fails
        data
      end
    end
  end
end

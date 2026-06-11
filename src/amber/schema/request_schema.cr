# Concrete implementation for request validation schemas
module Amber::Schema
  class RequestSchema < Definition
    def validate(data : Hash(String, JSON::Any)) : LegacyResult
      result = LegacyResult.new(true, data, data)
      context = Validator::Context.new(data, result, self)

      # Validate required fields
      self.class.required_fields.each do |field_name|
        validator = Validator::Required.new(field_name)
        validator.validate(context)
      end

      # Validate field types and constraints
      self.class.fields.each do |field_name, field_def|
        if data.has_key?(field_name)
          # Type validation
          type_validator = Validator::Type.new(field_name, field_def.type)
          type_validator.validate(context)

          # Field-specific validators
          field_def.validators.each do |validator|
            validator.validate(context)
          end
        end
      end

      # Run custom validators
      self.class.validators.each do |validator|
        validator.validate(context)
      end

      result
    end

    def parse(data : Hash(String, JSON::Any)) : LegacyResult
      # First validate
      validation_result = validate(data)
      return validation_result if validation_result.failure?

      # Then parse/transform
      parsed_data = {} of String => JSON::Any
      parser_context = Parser::Context.new(data, self)

      self.class.fields.each do |field_name, field_def|
        if value = data[field_name]?
          # Apply type coercion
          parser = Parser::TypeCoercion.new(field_def.type)
          parsed_value = parser.parse(value)
          parsed_data[field_name] = parsed_value
        elsif field_def.default
          parsed_data[field_name] = field_def.default
        end
      end

      # Create result with parsed data
      result = LegacyResult.success(parsed_data)

      # Copy any warnings from parser context
      parser_context.errors.each do |error|
        result.add_warning(Warning.new(error.field, error.message, error.code))
      end

      result
    end
  end
end

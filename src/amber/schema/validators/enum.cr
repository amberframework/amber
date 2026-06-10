# Enum validation - ensures value is one of allowed values
module Amber::Schema::Validator
  class Enum < Base
    @field_name : String
    @allowed_values : Array(JSON::Any)
    @allowed_string_representations : Array(String)
    @enum_type : String

    def initialize(@field_name : String, allowed_values : Array(String) | Array(Int32) | Array(Float64))
      if allowed_values.empty?
        raise ArgumentError.new("Enum validator requires at least one allowed value")
      end

      # Store original allowed values with their types preserved
      @allowed_values = allowed_values.map { |v| JSON::Any.new(v) }

      # Also store string representations for error messages
      @allowed_string_representations = allowed_values.map(&.to_s)

      # Determine the enum type for validation logic
      @enum_type = case allowed_values
                   when Array(String)
                     "String"
                   when Array(Int32)
                     "Int32"
                   when Array(Float64)
                     "Float64"
                   else
                     "String" # fallback
                   end
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)

      # Skip validation for nil values
      return if value.raw.nil?

      # Check if the value matches any allowed value
      unless value_matches_enum?(value)
        allowed_str = @allowed_string_representations.join(", ")
        context.add_error(
          CustomValidationError.new(
            @field_name,
            "Field '#{@field_name}' must be one of: #{allowed_str}",
            "invalid_enum_value"
          )
        )
      end
    end

    private def value_matches_enum?(value : JSON::Any) : Bool
      case @enum_type
      when "String"
        # For string enums, allow type coercion - convert incoming value to string and compare
        value_as_string = extract_value(value).to_s
        @allowed_string_representations.includes?(value_as_string)
      when "Int32", "Float64"
        # For numeric enums, be strict about types - only allow exact type matches
        extracted_value = extract_value(value)

        @allowed_values.any? do |allowed|
          allowed_extracted = extract_value(allowed)

          # Strict type and value comparison for numeric enums
          case {extracted_value, allowed_extracted}
          when {Int32, Int32}, {Int64, Int64}
            extracted_value == allowed_extracted
          when {Float32, Float32}, {Float64, Float64}
            extracted_value == allowed_extracted
          else
            false
          end
        end
      else
        # Fallback to string comparison
        value_as_string = extract_value(value).to_s
        @allowed_string_representations.includes?(value_as_string)
      end
    end

    private def extract_value(value : JSON::Any)
      case value.raw
      when String
        value.as_s
      when Int32, Int64
        value.as_i
      when Float32, Float64
        value.as_f
      when Bool
        value.as_bool
      else
        value.raw
      end
    end
  end
end

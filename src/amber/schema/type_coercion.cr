# Type coercion system for Schema API
# Provides flexible and extensible type conversion from strings to Crystal types
module Amber::Schema
  module TypeCoercion
    # Alias for custom coercion functions
    alias CoercionFunction = Proc(JSON::Any, JSON::Any?)

    # Registry for custom type coercion functions
    @@custom_coercions = {} of String => CoercionFunction

    # Common boolean string representations
    TRUE_VALUES  = {"true", "1", "yes", "y", "on", "t", "enabled", "active"}
    FALSE_VALUES = {"false", "0", "no", "n", "off", "f", "disabled", "inactive"}

    # Common time formats for parsing
    TIME_FORMATS = [
      "%Y-%m-%dT%H:%M:%S.%LZ",   # ISO8601 with milliseconds and Z
      "%Y-%m-%dT%H:%M:%S.%L%:z", # ISO8601 with milliseconds and timezone
      "%Y-%m-%dT%H:%M:%S%:z",    # ISO8601 with timezone
      "%Y-%m-%dT%H:%M:%SZ",      # ISO8601 with Z
      "%Y-%m-%d %H:%M:%S",       # Common format
      "%Y-%m-%d %H:%M:%S %z",    # Common format with timezone
      "%Y-%m-%d %H:%M:%S.%L",    # Common format with milliseconds
      "%Y/%m/%d %H:%M:%S",       # Alternative format
      "%Y-%m-%d",                # Date only (unambiguous)
      "%Y/%m/%d",                # Date only with slashes (unambiguous)
      "%m/%d/%Y %H:%M:%S",       # American format
      "%d/%m/%Y %H:%M:%S",       # European format
      "%m-%d-%Y",                # American date
      "%d-%m-%Y",                # European date
      "%m/%d/%Y",                # American date with slashes
      "%d/%m/%Y",                # European date with slashes
    ]

    # Main coercion method
    def self.coerce(value : JSON::Any, target_type : String) : JSON::Any?
      # Return nil if value is null
      return nil if value.raw.nil?

      # Check for custom coercion first
      if custom_func = @@custom_coercions[target_type]?
        return custom_func.call(value)
      end

      # Handle built-in types
      case target_type
      when "String"
        coerce_to_string(value)
      when "Int32"
        coerce_to_int32(value)
      when "Int64"
        coerce_to_int64(value)
      when "Float32"
        coerce_to_float32(value)
      when "Float64"
        coerce_to_float64(value)
      when "Bool"
        coerce_to_bool(value)
      when "Time"
        coerce_to_time(value)
      when "UUID"
        coerce_to_uuid(value)
      when /^Array\((.+)\)$/
        element_type = $1
        coerce_to_array(value, element_type)
      when /^Hash\(String, (.+)\)$/
        value_type = $1
        coerce_to_hash(value, value_type)
      else
        # Try to handle as-is for unknown types
        value
      end
    rescue
      nil
    end

    # Register a custom coercion function for a type
    def self.register(type : String, &block : JSON::Any -> JSON::Any?)
      @@custom_coercions[type] = block
    end

    # Clear all custom coercions
    def self.clear_custom_coercions
      @@custom_coercions.clear
    end

    # Coercion implementations for built-in types

    private def self.coerce_to_string(value : JSON::Any) : JSON::Any?
      case raw = value.raw
      when String
        value
      when Number
        JSON::Any.new(raw.to_s)
      when Bool
        JSON::Any.new(raw.to_s)
      else
        JSON::Any.new(value.to_s)
      end
    end

    private def self.coerce_to_int32(value : JSON::Any) : JSON::Any?
      case raw = value.raw
      when Int32
        value
      when Int64
        if raw >= Int32::MIN && raw <= Int32::MAX
          JSON::Any.new(raw.to_i32)
        else
          nil
        end
      when Float32, Float64
        int_value = raw.to_i64
        if int_value >= Int32::MIN && int_value <= Int32::MAX && raw == int_value
          JSON::Any.new(int_value.to_i32)
        else
          nil
        end
      when String
        # Handle empty string
        return nil if raw.empty?

        # Try to parse
        if int_value = raw.to_i32?
          JSON::Any.new(int_value)
        else
          nil
        end
      else
        nil
      end
    end

    private def self.coerce_to_int64(value : JSON::Any) : JSON::Any?
      case raw = value.raw
      when Int64
        value
      when Int32
        JSON::Any.new(raw.to_i64)
      when Float32, Float64
        int_value = raw.to_i64
        if raw == int_value
          JSON::Any.new(int_value)
        else
          nil
        end
      when String
        # Handle empty string
        return nil if raw.empty?

        # Try to parse
        if int_value = raw.to_i64?
          JSON::Any.new(int_value)
        else
          nil
        end
      else
        nil
      end
    end

    private def self.coerce_to_float32(value : JSON::Any) : JSON::Any?
      case raw = value.raw
      when Float32
        value
      when Float64
        JSON::Any.new(raw.to_f32)
      when Int32, Int64
        JSON::Any.new(raw.to_f32)
      when String
        # Handle empty string
        return nil if raw.empty?

        # Try to parse
        if float_value = raw.to_f32?
          JSON::Any.new(float_value)
        else
          nil
        end
      else
        nil
      end
    end

    private def self.coerce_to_float64(value : JSON::Any) : JSON::Any?
      case raw = value.raw
      when Float64
        value
      when Float32
        JSON::Any.new(raw.to_f64)
      when Int32, Int64
        JSON::Any.new(raw.to_f64)
      when String
        # Handle empty string
        return nil if raw.empty?

        # Try to parse
        if float_value = raw.to_f64?
          JSON::Any.new(float_value)
        else
          nil
        end
      else
        nil
      end
    end

    private def self.coerce_to_bool(value : JSON::Any) : JSON::Any?
      case raw = value.raw
      when Bool
        value
      when String
        normalized = raw.downcase.strip

        if TRUE_VALUES.includes?(normalized)
          JSON::Any.new(true)
        elsif FALSE_VALUES.includes?(normalized)
          JSON::Any.new(false)
        else
          nil
        end
      when Int32, Int64
        case raw
        when 0
          JSON::Any.new(false)
        when 1
          JSON::Any.new(true)
        else
          nil
        end
      when Float32, Float64
        case raw
        when 0.0
          JSON::Any.new(false)
        when 1.0
          JSON::Any.new(true)
        else
          nil
        end
      else
        nil
      end
    end

    private def self.coerce_to_time(value : JSON::Any) : JSON::Any?
      case raw = value.raw
      when String
        # Handle empty string
        return nil if raw.empty?

        # Try parsing with each format
        TIME_FORMATS.each do |format|
          begin
            time = Time.parse(raw, format, Time::Location::UTC)
            # Validate the parsed time makes sense (year should be reasonable)
            # This helps avoid issues like parsing "25-12-2023" as year 0025
            if time.year >= 1000 && time.year <= 9999
              # Return the ISO8601 string representation
              return JSON::Any.new(time.to_rfc3339)
            end
          rescue Time::Format::Error
            # Continue to next format
          rescue ArgumentError
            # Invalid date (e.g., month 25)
            # Continue to next format
          end
        end

        # Try ISO8601 parsing as fallback
        begin
          time = Time.parse_iso8601(raw)
          return JSON::Any.new(time.to_rfc3339)
        rescue
          nil
        end
      when Int32, Int64
        # Treat as Unix timestamp
        begin
          time = Time.unix(raw.to_i64)
          JSON::Any.new(time.to_rfc3339)
        rescue
          nil
        end
      else
        nil
      end
    end

    private def self.coerce_to_uuid(value : JSON::Any) : JSON::Any?
      case raw = value.raw
      when String
        # Handle empty string
        return nil if raw.empty?

        # Validate UUID format
        begin
          uuid = UUID.new(raw)
          JSON::Any.new(uuid.to_s)
        rescue
          nil
        end
      else
        nil
      end
    end

    private def self.coerce_to_file(value : JSON::Any) : JSON::Any?
      case raw = value.raw
      when Hash
        # This should be a file upload hash with filename, content_type, etc
        hash_value = raw.as(Hash(String, JSON::Any))

        # Validate that it has the expected file upload structure
        if hash_value.has_key?("filename") && hash_value.has_key?("content")
          value # Return the file data as-is
        else
          nil
        end
      else
        nil
      end
    end

    private def self.coerce_to_array(value : JSON::Any, element_type : String) : JSON::Any?
      case raw = value.raw
      when Array
        # Already an array, coerce elements
        coerced_elements = [] of JSON::Any
        raw.each do |element|
          if coerced = coerce(element, element_type)
            coerced_elements << coerced
          end
        end

        JSON::Any.new(coerced_elements)
      when String
        # Try to parse as JSON array
        begin
          parsed = JSON.parse(raw)
          if parsed_array = parsed.as_a?
            coerce_to_array(parsed, element_type)
          else
            # Parsed as JSON but not an array, wrap it
            if coerced = coerce(parsed, element_type)
              JSON::Any.new([coerced])
            else
              nil
            end
          end
        rescue
          # Not valid JSON, try comma-separated values for simple types
          case element_type
          when "String", "Int32", "Int64", "Float32", "Float64"
            elements = raw.split(',').map(&.strip)
            coerced_elements = [] of JSON::Any
            elements.each do |elem|
              if coerced = coerce(JSON::Any.new(elem), element_type)
                coerced_elements << coerced
              end
            end
            JSON::Any.new(coerced_elements)
          else
            nil
          end
        end
      else
        # Single value, try to coerce and wrap in array
        if coerced = coerce(value, element_type)
          JSON::Any.new([coerced])
        else
          nil
        end
      end
    end

    private def self.coerce_to_hash(value : JSON::Any, value_type : String) : JSON::Any?
      case raw = value.raw
      when Hash
        # Already a hash, coerce values
        coerced_hash = {} of String => JSON::Any

        raw.each do |key, val|
          key_str = key.to_s
          # Special handling for JSON::Any - don't coerce, just keep as-is
          if value_type == "JSON::Any"
            coerced_hash[key_str] = val.is_a?(JSON::Any) ? val : JSON::Any.new(val)
          elsif coerced = coerce(val, value_type)
            coerced_hash[key_str] = coerced
          end
        end

        JSON::Any.new(coerced_hash)
      when String
        # Try to parse as JSON object
        begin
          parsed = JSON.parse(raw)
          if parsed_hash = parsed.as_h?
            coerce_to_hash(parsed, value_type)
          else
            nil
          end
        rescue
          nil
        end
      else
        nil
      end
    end

    # Error information for coercion failures
    struct CoercionError
      getter field : String
      getter source_type : String
      getter target_type : String
      getter value : String

      def initialize(@field : String, @source_type : String, @target_type : String, @value : String)
      end

      def message : String
        "Cannot coerce #{field} from #{source_type} (#{value}) to #{target_type}"
      end
    end

    # Utility method to check if a value can be coerced to a type
    def self.can_coerce?(value : JSON::Any, target_type : String) : Bool
      !coerce(value, target_type).nil?
    end

    # Get a descriptive error for a failed coercion
    def self.coercion_error(field : String, value : JSON::Any, target_type : String) : CoercionError
      source_type = case value.raw
                    when String  then "String"
                    when Int32   then "Int32"
                    when Int64   then "Int64"
                    when Float32 then "Float32"
                    when Float64 then "Float64"
                    when Bool    then "Bool"
                    when Array   then "Array"
                    when Hash    then "Hash"
                    when Nil     then "Nil"
                    else              value.raw.class.to_s
                    end

      CoercionError.new(
        field: field,
        source_type: source_type,
        target_type: target_type,
        value: value.to_s
      )
    end
  end
end

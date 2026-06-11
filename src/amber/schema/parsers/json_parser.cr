# JSON parser for request bodies
module Amber::Schema::Parser
  class JSONParser < Base
    # Instance methods for Parser::Base interface
    def parse(value : JSON::Any) : JSON::Any
      # If it's already JSON::Any, return as-is
      value
    end

    def can_parse?(value : JSON::Any) : Bool
      true
    end

    # Class methods for parsing different input types

    # Parse raw JSON string into Hash suitable for schema validation
    def self.parse_string(json_string : String) : Hash(String, JSON::Any)
      return {} of String => JSON::Any if json_string.empty?

      json = JSON.parse(json_string)
      extract_fields(json)
    rescue ex : JSON::ParseException
      raise SchemaDefinitionError.new("Invalid JSON: #{ex.message}")
    end

    # Parse HTTP request body
    def self.parse_request(request : HTTP::Request) : Hash(String, JSON::Any)
      body = request.body.try(&.gets_to_end) || ""
      parse_string(body)
    end

    # Parse HTTP::Params into JSON-compatible hash with proper nesting
    def self.parse_params(params : HTTP::Params) : Hash(String, JSON::Any)
      result = {} of String => JSON::Any
      array_values = {} of String => Array(String)

      # First pass: collect array values
      params.each do |key, value|
        if key.ends_with?("[]")
          base_key = key[0..-3]
          array_values[base_key] ||= [] of String
          array_values[base_key] << value
        else
          set_nested_value(result, key, value)
        end
      end

      # Second pass: add arrays to result
      array_values.each do |key, values|
        result[key] = JSON::Any.new(values.map { |v| parse_value(v) })
      end

      result
    end

    # Parse multipart form data with file upload support
    def self.parse_multipart(params : Hash(String, String | Array(String)) | Hash(String, String | Array(String) | HTTP::FormData::Part)) : Hash(String, JSON::Any)
      result = {} of String => JSON::Any

      params.each do |key, value|
        case value
        when String
          set_nested_value(result, key, value)
        when Array(String)
          # Handle array parameters
          if key.ends_with?("[]")
            base_key = key[0..-3]
            result[base_key] = JSON::Any.new(value.map { |v| parse_value(v) })
          else
            # If not using [] notation, just store as array
            result[key] = JSON::Any.new(value.map { |v| parse_value(v) })
          end
        when HTTP::FormData::Part
          # Handle file uploads
          file_info = {
            "filename"     => JSON::Any.new(value.filename || ""),
            "content_type" => JSON::Any.new(value.headers["Content-Type"]? || "application/octet-stream"),
            "size"         => JSON::Any.new(value.body.size.to_i64),
          }
          set_nested_value(result, key, file_info)
        end
      end

      result
    end

    # Extract fields from JSON structure based on schema definition
    def self.extract_fields(json : JSON::Any, schema : Definition? = nil) : Hash(String, JSON::Any)
      case json.raw
      when Hash
        extract_from_hash(json.as_h, schema)
      when Array
        # If root is array, wrap in data key
        {"data" => json}
      else
        # If root is primitive, wrap in value key
        {"value" => json}
      end
    end

    # Extract fields from hash with aliasing support
    private def self.extract_from_hash(hash : Hash(String, JSON::Any), schema : Definition? = nil) : Hash(String, JSON::Any)
      result = {} of String => JSON::Any

      if schema
        # Use schema definition to guide extraction
        schema.class.fields.each do |field_name, field_def|
          # Check for 'as' option for aliasing
          source_name = field_def.options["as"]?.try(&.as_s) || field_name

          if hash.has_key?(source_name)
            result[field_name] = process_field_value(hash[source_name], field_def)
          elsif hash.has_key?(field_name)
            result[field_name] = process_field_value(hash[field_name], field_def)
          end
        end

        # Include any extra fields not in schema (for flexibility)
        hash.each do |key, value|
          unless result.has_key?(key)
            result[key] = value
          end
        end
      else
        # No schema, include all fields
        result = hash
      end

      result
    end

    # Process field value according to field definition
    private def self.process_field_value(value : JSON::Any, field_def : Definition::FieldDef) : JSON::Any
      # Handle nested schemas
      if field_def.options["nested_schema"]?
        case value.raw
        when Hash
          value # Keep as JSON::Any for nested schema to process
        else
          raise SchemaDefinitionError.new("Expected object for nested schema field '#{field_def.name}', got #{value.raw.class}")
        end
      else
        value
      end
    end

    # Set nested value in hash using dot notation or bracket notation
    private def self.set_nested_value(hash : Hash(String, JSON::Any), key : String, value : String | Hash(String, JSON::Any))
      # Handle different key formats
      if key.includes?("[") && key.includes?("]")
        # Bracket notation: user[name] or user[address][city]
        parse_bracket_notation(hash, key, value)
      elsif key.includes?(".")
        # Dot notation: user.name or user.address.city
        parse_dot_notation(hash, key, value)
      elsif key.ends_with?("[]")
        # Array notation
        base_key = key[0..-3]
        hash[base_key] ||= JSON::Any.new([] of JSON::Any)
        if array = hash[base_key].as_a?
          array << parse_value(value)
        end
      else
        # Simple key
        hash[key] = parse_value(value)
      end
    end

    # Parse bracket notation keys with array index support
    private def self.parse_bracket_notation(hash : Hash(String, JSON::Any), key : String, value : String | Hash(String, JSON::Any))
      # Parse keys like: user[profile][name] or items[0] or tags[1][name]
      parts = key.split(/[\[\]]/).reject(&.empty?)

      if parts.size == 1
        hash[parts[0]] = parse_value(value)
        return
      end

      # Navigate/create the nested structure
      current_hash : Hash(String, JSON::Any)? = hash
      current_array : Array(JSON::Any)? = nil

      parts[0..-2].each_with_index do |part, index|
        if index == 0
          # First part is always a key in the main hash
          if ch = current_hash
            if is_numeric?(parts[1]?)
              # Next part is numeric, so this should be an array
              ch[part] ||= JSON::Any.new([] of JSON::Any)
              if array = ch[part].as_a?
                current_array = array
                current_hash = nil
              else
                # Type conflict - skip this parameter
                return
              end
            else
              # Next part is not numeric, so this should be an object
              ch[part] ||= JSON::Any.new({} of String => JSON::Any)
              if obj = ch[part].as_h?
                current_hash = obj
              else
                # Type conflict - skip this parameter
                return
              end
            end
          end
        else
          # Subsequent parts - need to handle based on current context
          if current_array
            # We're navigating within an array
            if is_numeric?(part)
              # This is an array index
              array_index = part.to_i
              extend_array_to_index(current_array, array_index)

              # Check if next part exists and what it is
              if next_part = parts[index + 1]?
                if is_numeric?(next_part)
                  # Next is also numeric, create nested array
                  current_array[array_index] ||= JSON::Any.new([] of JSON::Any)
                  if nested_array = current_array[array_index].as_a?
                    current_array = nested_array
                  else
                    return
                  end
                else
                  # Next is object key, create nested object
                  current_array[array_index] ||= JSON::Any.new({} of String => JSON::Any)
                  if nested_obj = current_array[array_index].as_h?
                    current_hash = nested_obj
                    current_array = nil
                  else
                    return
                  end
                end
              end
            else
              # Non-numeric part after array - shouldn't happen in well-formed input
              return
            end
          elsif ch = current_hash
            # We're navigating within an object
            if is_numeric?(part)
              # Skip - this should have been handled as an array creation
              return
            else
              # Check if the NEXT part is numeric to determine if this should be an array
              if index + 1 < parts.size && is_numeric?(parts[index + 1]?)
                # Next part is numeric, so this should be an array
                ch[part] ||= JSON::Any.new([] of JSON::Any)
                if nested_array = ch[part].as_a?
                  current_array = nested_array
                  current_hash = nil
                else
                  return
                end
              else
                # This creates a nested object
                ch[part] ||= JSON::Any.new({} of String => JSON::Any)
                if nested_obj = ch[part].as_h?
                  current_hash = nested_obj
                else
                  return
                end
              end
            end
          end
        end
      end

      # Set the final value
      final_part = parts.last
      if ca = current_array
        if is_numeric?(final_part)
          # Setting array element
          array_index = final_part.to_i
          extend_array_to_index(ca, array_index)
          ca[array_index] = parse_value(value)
        end
      elsif ch = current_hash
        # Setting object property
        ch[final_part] = parse_value(value)
      end
    end

    # Helper method to check if a string represents a number
    private def self.is_numeric?(str : String?) : Bool
      return false unless str
      !!(str =~ /^\d+$/)
    end

    # Helper method to extend array to accommodate index
    private def self.extend_array_to_index(array : Array(JSON::Any), index : Int32)
      while array.size <= index
        array << JSON::Any.new(nil)
      end
    end

    # Parse dot notation keys
    private def self.parse_dot_notation(hash : Hash(String, JSON::Any), key : String, value : String | Hash(String, JSON::Any))
      parts = key.split('.')

      if parts.size == 1
        hash[parts[0]] = parse_value(value)
        return
      end

      current = hash
      parts[0..-2].each do |part|
        current[part] ||= JSON::Any.new({} of String => JSON::Any)
        if obj = current[part].as_h?
          current = obj
        else
          # Type conflict - skip this parameter
          return
        end
      end

      current[parts.last] = parse_value(value)
    end

    # Parse string value to appropriate JSON type
    private def self.parse_value(value : String | Hash(String, JSON::Any)) : JSON::Any
      case value
      when Hash(String, JSON::Any)
        JSON::Any.new(value)
      when String
        # Empty string = nil (for form compatibility)
        return JSON::Any.new(nil) if value.empty?

        # Try boolean
        return JSON::Any.new(true) if value.downcase == "true"
        return JSON::Any.new(false) if value.downcase == "false"

        # Try null
        return JSON::Any.new(nil) if value.downcase == "null"

        # Try integer (including negative)
        if value =~ /^-?\d+$/ && (int_value = value.to_i64?)
          return JSON::Any.new(int_value)
        end

        # Try float (including scientific notation)
        if value =~ /^-?\d*\.?\d+([eE][+-]?\d+)?$/ && (float_value = value.to_f64?)
          return JSON::Any.new(float_value)
        end

        # Try to parse as JSON (for nested objects/arrays in query strings)
        if (value.starts_with?("{") && value.ends_with?("}")) ||
           (value.starts_with?("[") && value.ends_with?("]"))
          begin
            return JSON.parse(value)
          rescue
            # Not valid JSON, treat as string
          end
        end

        # Default to string
        JSON::Any.new(value)
      else
        JSON::Any.new(value.to_s)
      end
    end

    # Validate JSON against schema (used for error reporting)
    def self.validate_json(json : JSON::Any, schema : Definition) : Array(Error)
      errors = [] of Error

      case json.raw
      when Hash
        validate_object(json.as_h, schema, errors)
      else
        errors << TypeMismatchError.new("", "Object", json.raw.class.to_s)
      end

      errors
    end

    # Validate object against schema
    private def self.validate_object(obj : Hash(String, JSON::Any), schema : Definition, errors : Array(Error), path : String = "")
      # Check for unexpected fields if schema is strict
      if schema.class.responds_to?(:strict?) && schema.class.strict?
        obj.each_key do |key|
          unless schema.class.has_field?(key)
            field_path = path.empty? ? key : "#{path}.#{key}"
            errors << CustomValidationError.new(field_path, "Unexpected field", "unexpected_field")
          end
        end
      end

      # Validate nested objects
      schema.class.fields.each do |field_name, field_def|
        if field_def.type.includes?("Hash") && obj.has_key?(field_name)
          if nested = obj[field_name].as_h?
            # Recursively validate nested objects if they have a schema
            if nested_schema_class = field_def.options["nested_schema"]?
              # Would need to instantiate and validate nested schema here
            end
          end
        end
      end
    end

    # Create detailed parse error with context
    def self.create_parse_error(json_string : String, error : JSON::ParseException) : SchemaDefinitionError
      # JSON::ParseException in Crystal doesn't expose location details,
      # so we'll just return a simple error message
      SchemaDefinitionError.new("Invalid JSON: #{error.message}")
    end
  end
end

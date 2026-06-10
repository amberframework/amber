# Type validation for schema fields
module Amber::Schema::Validator
  class Type < Base
    @expected_type : String
    @field_name : String

    def initialize(@field_name : String, @expected_type : String)
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)

      unless valid_type?(value)
        actual_type = detect_json_type(value)
        context.add_error(TypeMismatchError.new(@field_name, @expected_type, actual_type))
      end
    end

    private def valid_type?(value : JSON::Any) : Bool
      case @expected_type
      when "String"
        !value.as_s?.nil?
      when "Int32"
        !value.as_i?.nil?
      when "Int64"
        !value.as_i64?.nil?
      when "Float32", "Float64"
        !value.as_f?.nil? || !value.as_i?.nil?
      when "Bool"
        !value.as_bool?.nil?
      when /^Array\(/
        !value.as_a?.nil?
      when /^Hash\(/
        !value.as_h?.nil?
      when "Time"
        if str = value.as_s?
          begin
            Time.parse_iso8601(str)
            true
          rescue
            false
          end
        else
          false
        end
      else
        true
      end
    rescue
      false
    end

    private def detect_json_type(value : JSON::Any) : String
      case value.raw
      when String
        "String"
      when Int
        "Integer"
      when Float
        "Float"
      when Bool
        "Boolean"
      when Array
        "Array"
      when Hash
        "Object"
      when Nil
        "Null"
      else
        "Unknown"
      end
    end
  end
end

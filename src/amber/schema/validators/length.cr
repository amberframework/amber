# Length validation for strings and arrays
module Amber::Schema::Validator
  # Validates exact length or length range
  class Length < Base
    def initialize(@field_name : String, @min : Int32? = nil, @max : Int32? = nil)
      if @min.nil? && @max.nil?
        raise ArgumentError.new("Length validator requires at least min or max")
      end
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)

      length = case value.raw
               when String
                 value.as_s.size
               when Array
                 value.as_a.size
               else
                 return # Skip validation for non-string/array types
               end

      if @min && length < @min.not_nil!
        context.add_error(LengthError.new(@field_name, @min, @max, length))
      elsif @max && length > @max.not_nil!
        context.add_error(LengthError.new(@field_name, @min, @max, length))
      end
    end
  end

  # Validates minimum length
  class MinLength < Base
    def initialize(@field_name : String, @min : Int32)
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)

      length = case value.raw
               when String
                 value.as_s.size
               when Array
                 value.as_a.size
               else
                 return # Skip validation for non-string/array types
               end

      if length < @min
        context.add_error(LengthError.new(@field_name, @min, nil, length))
      end
    end
  end

  # Validates maximum length
  class MaxLength < Base
    def initialize(@field_name : String, @max : Int32)
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)

      length = case value.raw
               when String
                 value.as_s.size
               when Array
                 value.as_a.size
               else
                 return # Skip validation for non-string/array types
               end

      if length > @max
        context.add_error(LengthError.new(@field_name, nil, @max, length))
      end
    end
  end
end

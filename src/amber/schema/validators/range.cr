# Range validation for numeric values
module Amber::Schema::Validator
  # Validates numeric range (both min and max)
  class Range < Base
    def initialize(@field_name : String, @min : Float64? = nil, @max : Float64? = nil)
      if @min.nil? && @max.nil?
        raise ArgumentError.new("Range validator requires at least min or max")
      end
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)

      number = case value.raw
               when Int
                 value.as_i.to_f64
               when Float
                 value.as_f
               else
                 return # Skip validation for non-numeric types
               end

      if @min && number < @min.not_nil!
        context.add_error(RangeError.new(@field_name, @min, @max, number))
      elsif @max && number > @max.not_nil!
        context.add_error(RangeError.new(@field_name, @min, @max, number))
      end
    end
  end

  # Validates minimum value
  class Min < Base
    def initialize(@field_name : String, @min : Float64)
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)

      number = case value.raw
               when Int
                 value.as_i.to_f64
               when Float
                 value.as_f
               else
                 return # Skip validation for non-numeric types
               end

      if number < @min
        context.add_error(RangeError.new(@field_name, @min, nil, number))
      end
    end
  end

  # Validates maximum value
  class Max < Base
    def initialize(@field_name : String, @max : Float64)
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)

      number = case value.raw
               when Int
                 value.as_i.to_f64
               when Float
                 value.as_f
               else
                 return # Skip validation for non-numeric types
               end

      if number > @max
        context.add_error(RangeError.new(@field_name, nil, @max, number))
      end
    end
  end
end

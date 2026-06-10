# Base validator module and classes
module Amber::Schema
  module Validator
    # Base class for all validators
    abstract class Base
      abstract def validate(context : Context) : Nil
    end

    # Validation context passed to validators
    class Context
      getter data : Hash(String, JSON::Any)
      getter result : LegacyResult
      getter schema : Definition

      def initialize(@data : Hash(String, JSON::Any), @result : LegacyResult, @schema : Definition)
      end

      # Helper methods for validators
      def field_exists?(name : String) : Bool
        @data.has_key?(name)
      end

      def field_value(name : String) : JSON::Any?
        @data[name]?
      end

      def add_error(error : Error)
        @result.add_error(error)
      end

      def add_warning(warning : Warning)
        @result.add_warning(warning)
      end
    end

    # Custom validator that accepts a block
    class Custom < Base
      def initialize(&@block : Context ->)
      end

      def validate(context : Context) : Nil
        @block.call(context)
      end
    end

    # Field-specific validator
    class Field(T) < Base
      def initialize(@field_name : String, &@block : T ->)
      end

      def validate(context : Context) : Nil
        if value = context.field_value(@field_name)
          begin
            typed_value = value.as(T)
            @block.call(typed_value)
          rescue TypeCastError
            # Type mismatch will be handled by type validator
          end
        end
      end
    end

    # Composite validator that runs multiple validators
    class Composite < Base
      getter validators : Array(Base) = [] of Base

      def initialize(@validators : Array(Base))
      end

      def validate(context : Context) : Nil
        @validators.each do |validator|
          validator.validate(context)
        end
      end
    end

    # Conditional validator that only runs if a condition is met
    class Conditional < Base
      def initialize(@condition : Context -> Bool, @validator : Base)
      end

      def validate(context : Context) : Nil
        if @condition.call(context)
          @validator.validate(context)
        end
      end
    end
  end
end

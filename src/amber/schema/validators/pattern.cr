# Pattern/Regex validation for strings
module Amber::Schema::Validator
  class Pattern < Base
    def initialize(@field_name : String, @pattern : Regex, @message : String? = nil)
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)
      return unless string_value = value.as_s?

      unless @pattern.matches?(string_value)
        message = @message || "Field '#{@field_name}' does not match required pattern"
        context.add_error(CustomValidationError.new(@field_name, message, "pattern_mismatch"))
      end
    end
  end
end

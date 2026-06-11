# Validator for required fields
module Amber::Schema::Validator
  class Required < Base
    def initialize(@field_name : String)
    end

    def validate(context : Context) : Nil
      unless context.field_exists?(@field_name)
        context.add_error(RequiredFieldError.new(@field_name))
      else
        value = context.field_value(@field_name)
        if value.nil? || value.raw.nil? || (value.as_s? && value.as_s.empty?)
          context.add_error(RequiredFieldError.new(@field_name))
        end
      end
    end
  end
end

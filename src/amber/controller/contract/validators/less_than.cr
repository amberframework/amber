module Validators
  class LessThan < Validator
    def valid?
      value.as(Number) < expected_value.as(Number)
    end

    def message
      @message || "must be less than #{expected_value}"
    end
  end
end

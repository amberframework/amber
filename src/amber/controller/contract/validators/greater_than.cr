module Validators
  class GreaterThan < Validator
    def valid?
      value.as(Number) > expected_value.as(Number)
    end

    def message
      @message || "must be greater than #{expected_value}"
    end
  end
end

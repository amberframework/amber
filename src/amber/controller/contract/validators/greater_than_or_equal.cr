module Validators
  class GreaterThanOrEqual < Validator
    def valid?
      value.as(Number) >= expected_value.as(Number)
    end

    def message
      @message || "must be greater or equal to #{expected_value}"
    end
  end
end

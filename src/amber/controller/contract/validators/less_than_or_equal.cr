module Validators
  class LessThanOrEqual < Validator
    def valid?
      value.as(Number) < expected_value.as(Number)
    end

    def message
      @message || "must be less or equal to #{expected_value}"
    end
  end
end

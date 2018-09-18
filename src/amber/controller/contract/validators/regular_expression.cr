module Validators
  class RegularExpression < Validators::Validator
    def valid?
      match(value).match(expected_value)
    end

    def message
      @message || "must match #{expected_value}"
    end
  end
end

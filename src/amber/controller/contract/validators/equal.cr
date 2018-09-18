require "./validator"

module Validators
  class Equal < Validator
    def valid?
      value == expected_value
    end

    def message
      @message || "must be equal to #{expected_value}"
    end
  end
end

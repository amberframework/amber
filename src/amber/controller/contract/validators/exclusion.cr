module Validators
  class Exclusion < Validator
    def valid?
      case value
      when Array
        !expected_value.as(Array).includes?(value.as(Array).size)
      when Hash
        !expected_value.as(Hash).includes?(value.as(Hash).size)
      when Range
        !expected_value.as(Range).includes?(value.as(Range).size)
      else
        raise "Invalid Type"
      end
    end

    def message
      @message || "must not be in #{expected_value}"
    end
  end
end

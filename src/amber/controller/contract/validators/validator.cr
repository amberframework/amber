module Validators
  abstract class Validator
    property attribute : String | Symbol
    property value : Contract::Validation::Any
    property expected_value : Contract::Validation::Any

    def initialize(@attribute, @value, @expected_value = nil, @message : String? = nil)
    end

    def valid?
    end

    def message
      @message || "must be equal to #{expected_value}"
    end
  end
end

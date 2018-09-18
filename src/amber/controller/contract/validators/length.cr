module Validators
  class Length < Validator
    def valid?
      case expected_value
      when Array
        value.as(Array).size == expected_value.as(Array).size
      when Hash
        value.as(Hash).size == expected_value.as(Hash).size
      when Range
        case value
        when String
          expected_value.as(Range).includes?(value.as(String).size)
        when Array
          expected_value.as(Range).includes?(value.as(Array).size)
        when Hash
          expected_value.as(Range).includes?(value.as(Hash).size)
        end
      else
        raise "Invalid Type"
      end
    end

    def message
      @message || "must be of size #{expected_value}"
    end
  end
end

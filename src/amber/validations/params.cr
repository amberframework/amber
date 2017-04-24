require "../support/predicates"

# We are patching the String class and Number struct to extend the predicates
# available this will allow to add friendlier methods for validation cases.
class String
  include Amber::Support::Predicates::String
end

abstract struct Number
  include Amber::Support::Predicates::Number
end

module Amber::Validations
  class Params
    property raw_params : HTTP::Params = HTTP::Params.parse("t=t")
    property errors = {} of String => {String, String}
    property params = {} of String => String

    def initialize(@raw_params : HTTP::Params)
    end

    # Setups validation rules to be performed
    #
    # ```crystal
    # params.validation do
    #   required(:email) { |p| p.url? }
    #   required(:age, UInt32)
    # end
    # ```
    # returns Validator
    def validation(&block)
      validate do
        {{yield}}
      end
      self
    end

    # Input must be valid otherwise raises error, if valid returns a hash
    # of validated params Otherwise raises a Validator::ValidationFailed error
    # messages contain errors.
    #
    # ```crystal
    # user = User.new params.validate!
    # ```
    # returns validated parms hash String => String
    def validate!
      raise Amber::Exceptions::Validator::MissingValidationRules unless @captured.nil?
      validate(&callback) if callback = @captured
      raise Amber::Exceptions::Validator::ValidationFailed, errors unless errors.empty?
      params
    end

    # Validates the inputs, does not raise errors and returns the validated
    # params
    #
    # ```crystal
    # user = User.new params.validate!
    # ```
    # returns validated parms hash String => String
    def validate
      raise Amber::Exceptions::Validator::MissingValidationRules unless @captured.nil?
      validate(&callback) if callback = @captured
      params
    end

    # Returns True or false wether the validation passed
    #
    # ```crystal
    # unless params.valid?
    #   response.puts {errors: params.errors}.to_json
    #   response.status_code 400
    # end
    # ```
    # returns Boolean
    def valid?
      errors.empty?
    end

    # Captures and Prforms the validation rules block
    #
    # returns Nil
    private def validate(&block) : Nil
      capture_validation_block(&block)
      with self yield
    end

    # Validates each field with a given set of predicates returns true if the
    # field is valid otherwise returns false
    #
    # ```crystal
    # required(:email) { |p| p.email? & p.size.between? 1..10 }
    # ```
    private def required(key, msg : String?)
      return false unless raw_params.has_key? key
      field = raw_params[key]
      params[key] = field
      valid = yield field
      unless valid
        errors[key] = {params[key], msg || "#{message(key)}"}
      end
      valid
    end

    # Builds a message for given key if
    private def message(key)
      # TODO Implement i18n error messages
      "#{key.capitalize} is invalid."
    end

    # Captures the validation block into a local variable
    # Every time a validation block is defined is sets a the capture
    private def capture_validation_block(&block)
      @captured = block
    end
  end
end

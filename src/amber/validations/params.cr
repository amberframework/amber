require "../support/predicates"

# We are patching the String class and Number struct to extend the predicates
# available this will allow to add friendlier methods for validation cases.
class String
  include Amber::Support::Predicates::String
end

abstract struct Number
  include Amber::Support::Predicates::Number
end

module Amber::Validators
  class Params
    getter raw_params : HTTP::Params = HTTP::Params.parse("t=t")
    getter errors = {} of String => {String, String}
    getter params = {} of String => String

    def initialize(@raw_params : HTTP::Params); end

    # Setups validation rules to be performed
    #
    # ```crystal
    # params.validation do
    #   required(:email) { |p| p.url? }
    #   required(:age, UInt32)
    # end
    # ```
    def validation
      errors.clear
      params.clear
      with self yield
      self
    end

    # Input must be valid otherwise raises error, if valid returns a hash
    # of validated params Otherwise raises a Validator::ValidationFailed error
    # messages contain errors.
    #
    # ```crystal
    # user = User.new params.validate!
    # ```
    def validate!
      raise Amber::Exceptions::Validator::ValidationFailed.new errors unless errors.empty?
      params
    end

    # Validates the inputs, does not raise errors and returns the validated
    # params
    #
    # ```crystal
    # user = User.new params.validate!
    # ```
    def validate
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
    def valid?
      errors.empty?
    end

    # Captures and performs the validation rules block
    #
    # returns Nil
    private def validate
      with self yield
    end

    # Validates each field with a given set of predicates returns true if the
    # field is valid otherwise returns false
    #
    # ```crystal
    # required(:email) { |p| p.email? & p.size.between? 1..10 }
    # ```
    def required(key, msg : String? = nil)
      unless raw_params.has_key?(key)
        errors[key] = {"invalid", "Param [nonexisting] does not exist."}
        return false
      end

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
  end
end

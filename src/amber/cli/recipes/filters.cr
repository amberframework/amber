require "inflector"

module Liquid::Filters

  FilterRegister.register "pluralize", Pluralize
  FilterRegister.register "underscore", Underscore
  FilterRegister.register "camelcase", CamelCase
  FilterRegister.register "camelize", CamelCase
  FilterRegister.register "upcase", UpCase
  FilterRegister.register "uppercase", UpCase

  # Uses the Inflector to camelize/camelcase a string.
  #
  # If the +uppercase_first_letter+ parameter is set to false, then produces
  # lowerCamelCase.
  #
  # Also converts "/" to "::" which is useful for converting
  # paths to namespaces.
  #
  #   camelize("active_model")                # => "ActiveModel"
  #   camelize("active_model", false)         # => "activeModel"
  #   camelize("active_model/errors")         # => "ActiveModel::Errors"
  #   camelize("active_model/errors", false)  # => "activeModel::Errors"
  #
  # As a rule of thumb you can think of +camelize+ as the inverse of
  # #underscore, though there are cases where that does not hold:
  #
  #   camelize(underscore("SSLError"))        # => "SslError"
  class CamelCase
    extend Filter

    def self.filter(data : Any, args : Array(Any)? = nil) : Any
      if (raw = data.raw) && raw.is_a? String
        Any.new Inflector.camelize(raw)
      else
        data
      end
    end
  end

  # pluralize
  #
  # Uses the Inflector to pluralize a string.
  #
  # Input
  # {{ "post" | pluralize }}
  #
  # Output
  # posts
  class Pluralize
    extend Filter

    def self.filter(data : Any, args : Array(Any)? = nil) : Any
      if (raw = data.raw) && raw.is_a? String
        Any.new Inflector.pluralize(raw)
      else
        data
      end
    end
  end

  # underscore
  #
  # Uses the Inflector to underscore a string.
  #
  # Input
  # {{ "ActiveModel" | underscore }}
  #
  # Output
  # active_model
  class Underscore
    extend Filter

    def self.filter(data : Any, args : Array(Any)? = nil) : Any
      if (raw = data.raw) && raw.is_a? String
        Any.new Inflector.underscore(raw)
      else
        data
      end
    end
  end

  # upcase | uppercase
  #
  # Uppercases all characters of a string.
  #
  # Input
  # {{ "word" | upcase }}  => WORD
  # {{ "word" | uppercase }}  => WORD
  #
  class UpCase
    extend Filter

    def self.filter(data : Any, args : Array(Any)? = nil) : Any
      if (raw = data.raw) && raw.is_a? String
        Any.new raw.as(String).upcase
      else
        data
      end
    end
  end

end

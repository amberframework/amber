require "inflector"

module Liquid::Filters

  FilterRegister.register "pluralize", Pluralize
  FilterRegister.register "underscore", Underscore

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

end

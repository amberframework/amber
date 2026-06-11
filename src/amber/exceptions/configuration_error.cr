module Amber::Exceptions
  class ConfigurationError < Exception
    getter list_of_errors : Array(String)

    def initialize(message : String)
      @list_of_errors = [message]
      super(message)
    end

    def initialize(@list_of_errors : Array(String))
      super("Configuration errors:\n" + @list_of_errors.map { |e| "  - #{e}" }.join("\n"))
    end
  end
end

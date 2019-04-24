module Amber::CLI
  class Auth < Generator
    command :auth
    property auth : Generator

    def initialize(name, fields)
      super(name, fields)
      case config.model
      when "clear"
        @auth = ClearAuth.new(name, fields)
      when "crecto"
        @auth = CrectoAuth.new(name, fields)
      else # "granite"
        @auth = GraniteAuth.new(name, fields)
      end
    end

    def render(directory)
      auth.render(directory)
    end
  end
end

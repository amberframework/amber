module Amber::CLI
  class Auth < Generator
    command :auth
    property auth : Generator

    def initialize(name, fields)
      super(name, fields)
      if config.model == "crecto"
        @auth = CrectoAuth.new(name, fields)
      else
        @auth = GraniteAuth.new(name, fields)
      end
    end

    def render(directory)
      auth.render(directory)
    end
  end
end

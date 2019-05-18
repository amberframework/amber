module Amber::CLI
  class Auth < Generator
    command :auth
    property auth : Generator

    def initialize(name, fields)
      super(name, fields)
      @auth = GraniteAuth.new(name, fields)
    end

    def render(directory)
      auth.render(directory)
    end
  end
end

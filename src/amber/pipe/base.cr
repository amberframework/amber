require "http"

module Amber
  module Pipe
    # The base class for Amber Pipes.  This extension provides a singleton
    # method and ability to configure each handler.  All configurations should
    # be maintained in the `/config` folder for consistency.
    class Base
      include HTTP::Handler

      # Ability to configure the singleton instance from the class
      def self.config
        yield self.instance
      end

      # Ability to configure the instance
      def config
        yield self
      end

      # Execution of this handler.
      def call(context : HTTP::Server::Context )
        call_next context
      end
    end
  end
end

require "../../support/client_reload"

module Amber
  module Pipe
    # Reload clients browsers using `ClientReload`.
    #
    # NOTE: Amber::Pipe::Reload is intended for use in a development environment.
    # ```
    # pipeline :web do
    #   plug Amber::Pipe::Reload.new
    # end
    # ```
    class Reload < Base
      def initialize
        Support::ClientReload.new
        super
      end

      def call(context : HTTP::Server::Context)
        if context.format == "html"
          context.response.print Support::ClientReload::INJECTED_CODE
        end
        call_next(context)
      end
    end
  end
end

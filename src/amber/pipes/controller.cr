module Amber
  module Pipe
    # This is the default last pipe which is inserted automatically
    # in order to call the controller action.

    class Controller < Base
      def call(context : HTTP::Server::Context)
        context.process_request
      end
    end
  end
end

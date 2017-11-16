module Amber
  module Pipe
    # The session handler provides a cookie based session.  The handler will
    # encode and decode the cookie and provide the hash in the context that can
    # be used to maintain data across requests.
    class Last < Base
      def call(context : HTTP::Server::Context)
        context.process_request
      end
    end
  end
end

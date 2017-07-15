module Amber
  module Pipe
    # The session handler provides a cookie based session.  The handler will
    # encode and decode the cookie and provide the hash in the context that can
    # be used to maintain data across requests.
    class Session < Base
      def call(context : HTTP::Server::Context)
        call_next(context)
        context.session.set_session
        context.cookies.write(context.response.headers)
        context
      end
    end
  end
end

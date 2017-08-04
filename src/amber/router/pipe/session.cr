module Amber
  module Pipe
    # The session handler provides a cookie based session.  The handler will
    # encode and decode the cookie and provide the hash in the context that can
    # be used to maintain data across requests.
    class Session < Base
      def call(context : HTTP::Server::Context)
        # Session has to be set before it can be use down the pipeline
        context.session.set_session

        call_next(context)
      ensure
        if context.session.changed?
          context.cookies.write(context.response.headers)
        end
      end
    end
  end
end

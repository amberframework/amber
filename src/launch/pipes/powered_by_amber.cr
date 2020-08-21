module Launch
  module Pipe
    class PoweredByLaunch < Base
      def call(context : HTTP::Server::Context)
        context.response.headers["X-Powered-By"] = "Launch"
        call_next(context)
      end
    end
  end
end

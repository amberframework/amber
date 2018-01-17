module Amber
  module Pipe
    # Adds header "X-Powered-By: Amber" to the response
    class PoweredByAmber < Base

      def call(context : HTTP::Server::Context)
        context.response.headers["X-Powered-By"] = "Amber"
      end
    end
  end
end

module Amber
  module Pipe
    # Handler to determine real client IP address when Amber is behind a
    # reverse proxy and save it to context.client_ip.
    #
    # The proxy should pass client IP in a header such as "X-Forwarded-For".
    # In case of multiple values in a header, the first one is used.
    #
    # Crystal does not currently make remote IP available, so it is impossible
    # to accept the header value only when coming from trusted proxy IPs.
    # For that and other benefits, it is suggested to always run Amber apps
    # behind proxies such as HAProxy or Nginx.
    class ClientIp < Base
      def initialize(header : String = "X-Forwarded-For")
        @headers = [header]
      end
      def initialize( @headers : Array(String))
      end

      def call(context : HTTP::Server::Context)
        @headers.each do |header|
          if addresses = context.request.headers.get?(header)
            context.client_ip = Socket::IPAddress.new(addresses[0], 0)
          end
        end
        call_next(context)
      end
    end
  end
end

class HTTP::Server::Context
  property client_ip : Socket::IPAddress?
end

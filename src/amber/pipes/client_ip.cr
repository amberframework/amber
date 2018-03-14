module Amber
  module Pipe
    # Handler to determine real client IP address when Amber is behind
    # trusted reverse proxy or proxies, and save it to context.client_ip.
    #
    # Reverse proxy should pass client IP in a header such as "X-Forwarded-For".
    # In case of multiple values in a header, the leftmost one is used.
    #
    # For this functionality to not cause security concerns, all trusted,
    # public-facing reverse proxies should delete the header if request is
    # coming from an untrusted client before appending their own, valid value.
    class ClientIp < Base
      def initialize(header : String = "X-Forwarded-For")
        @headers = [header]
      end

      def initialize(@headers : Array(String))
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

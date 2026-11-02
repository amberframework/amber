module Amber
  module Extensions
    module HTTPServerContext
      property client_ip : Socket::IPAddress?
    end

    module HTTPServerResponse
      # Returns `true` once the status line and headers have gone to the
      # client, after which neither can change.
      def headers_sent? : Bool
        wrote_headers?
      end
    end
  end
end

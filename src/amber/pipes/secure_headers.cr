module Amber
  module Pipe
    # The SecureHeaders pipe sets security-related HTTP headers to help
    # protect against common vulnerabilities like XSS, clickjacking, and MIME sniffing.
    class SecureHeaders < Base
      property? hsts : Bool

      def initialize(@hsts = false)
      end

      def call(context : HTTP::Server::Context)
        headers = context.response.headers

        # Prevent browser from guessing the MIME type
        headers["X-Content-Type-Options"] ||= "nosniff"

        # Prevent clickjacking by not allowing the page to be framed
        headers["X-Frame-Options"] ||= "SAMEORIGIN"

        # Enable XSS filtering in browsers
        headers["X-XSS-Protection"] ||= "1; mode=block"

        # Control how much referrer information is sent
        headers["Referrer-Policy"] ||= "strict-origin-when-cross-origin"

        # Enforce HTTPS connections (if enabled)
        if @hsts
          headers["Strict-Transport-Security"] ||= "max-age=31536000; includeSubDomains"
        end

        call_next(context)
      end
    end
  end
end

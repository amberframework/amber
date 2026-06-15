module Amber
  module Pipe
    # The SecureHeaders pipe sets security-related HTTP headers to help
    # protect against common vulnerabilities like XSS, clickjacking, and MIME sniffing.
    class SecureHeaders < Base
      def call(context : HTTP::Server::Context)
        headers = context.response.headers

        # Prevent browser from guessing the MIME type
        headers["X-Content-Type-Options"] ||= "nosniff"

        # Enable XSS filtering in browsers
        headers["X-XSS-Protection"] ||= "1; mode=block"

        # Prevent clickjacking by not allowing the page to be framed
        headers["X-Frame-Options"] ||= "SAMEORIGIN"

        # Enforce HTTPS connections (if using HTTPS)
        # Note: In a real production app, you might want to configure max-age or includeSubDomains
        headers["Strict-Transport-Security"] ||= "max-age=31536000; includeSubDomains"

        call_next(context)
      end
    end
  end
end

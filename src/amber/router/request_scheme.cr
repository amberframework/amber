require "../support/trusted_proxies"
require "./forwarded_header"

module Amber::Router
  # Decides which scheme, `"https"` or `"http"`, a client used to reach the
  # application. `HTTP::Request#scheme` and `HTTP::Request#https?` call it,
  # and everything in Amber that asks "is this request HTTPS" (the cookie
  # jar's Secure handling, and with it the session and CSRF cookies) goes
  # through those two methods.
  #
  # The scheme starts as the connection's own: `"https"` when Amber terminates
  # TLS itself (`server.ssl` is configured), otherwise `"http"`. When the
  # immediate peer is a trusted proxy, the scheme that proxy reported
  # replaces it, read in this order:
  #
  # 1. the `proto=` parameter of the last element of `Forwarded` (RFC 7239),
  # 2. the last value of `X-Forwarded-Proto`,
  # 3. the CGI-style `HTTPS: on` header.
  #
  # Each proxy appends its own element to the end of these headers, so the
  # last one is the value the trusted hop wrote; anything to its left came
  # from further away and is not trusted. A request whose peer is not a
  # trusted proxy keeps its real scheme whatever headers it carries.
  module RequestScheme
    HTTPS = "https"
    HTTP  = "http"

    private X_FORWARDED_PROTO_HEADER = "X-Forwarded-Proto"
    private CGI_HTTPS_HEADER         = "HTTPS"

    # Returns the scheme of *request*. *trusted_proxies* comes from the
    # `server.trusted_proxies` setting, and *server_terminates_tls* states
    # whether Amber itself accepted the connection over TLS.
    def self.resolve(request : ::HTTP::Request,
                     trusted_proxies : Amber::Support::TrustedProxies,
                     server_terminates_tls : Bool) : String
      connection_scheme = server_terminates_tls ? HTTPS : HTTP
      return connection_scheme unless trusted_proxies.trusts?(request.remote_address)

      headers = request.headers
      forwarded_proto(headers) || x_forwarded_proto(headers) || cgi_https_flag(headers) || connection_scheme
    end

    # Returns the `proto=` value of the last `Forwarded` element when it names
    # http or https.
    private def self.forwarded_proto(headers : ::HTTP::Headers) : String?
      last_proto = ForwardedHeader.list_of_parameter_values(headers, "proto").last?
      return unless last_proto

      known_scheme(last_proto)
    end

    # Returns the last `X-Forwarded-Proto` value when it names http or https.
    private def self.x_forwarded_proto(headers : ::HTTP::Headers) : String?
      last_value = ForwardedHeader.list_of_values(headers, X_FORWARDED_PROTO_HEADER).last?
      return unless last_value

      known_scheme(last_value)
    end

    # Returns `"https"` for the CGI convention `HTTPS: on`, which some proxies
    # and older Amber apps' own pipes set.
    private def self.cgi_https_flag(headers : ::HTTP::Headers) : String?
      flag = headers[CGI_HTTPS_HEADER]?
      return unless flag

      flag.strip.compare("on", case_insensitive: true) == 0 ? HTTPS : nil
    end

    private def self.known_scheme(value : String) : String?
      normalized = value.downcase
      return HTTPS if normalized == HTTPS
      return HTTP if normalized == HTTP

      nil
    end
  end
end

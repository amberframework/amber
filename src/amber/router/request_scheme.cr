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
  # replaces it. Amber reads only the header family the trusted proxies write
  # (`server.trusted_proxy_headers`), because a proxy passes the other family
  # through from the client unchanged:
  #
  # - `"x-forwarded"` (the default): the last value of `X-Forwarded-Proto`.
  # - `"forwarded"`: the `proto=` parameter of the last `Forwarded` element
  #   (RFC 7239).
  #
  # Each proxy appends its own value to the end of these headers, so the last
  # one is the value the trusted hop wrote; anything to its left came from
  # further away and is not trusted. A value other than http or https, or no
  # header at all, keeps the connection's scheme. Other headers, such as the
  # CGI-style `HTTPS: on`, are never read: a proxy passes them through from
  # the client unchanged. A request whose peer is not a trusted proxy keeps
  # its real scheme whatever headers it carries.
  module RequestScheme
    HTTPS = "https"
    HTTP  = "http"

    private X_FORWARDED_PROTO_HEADER = "X-Forwarded-Proto"

    # Returns the scheme of *request*. *trusted_proxies* comes from the
    # `server.trusted_proxies` and `server.trusted_proxy_headers` settings,
    # and *server_terminates_tls* states whether Amber itself accepted the
    # connection over TLS.
    def self.resolve(request : ::HTTP::Request,
                     trusted_proxies : Amber::Support::TrustedProxies,
                     server_terminates_tls : Bool) : String
      connection_scheme = server_terminates_tls ? HTTPS : HTTP
      return connection_scheme unless trusted_proxies.trusts?(request.remote_address)

      headers = request.headers
      reported_scheme = trusted_proxies.reads_forwarded_header? ? forwarded_proto(headers) : x_forwarded_proto(headers)
      reported_scheme || connection_scheme
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

    private def self.known_scheme(value : String) : String?
      normalized = value.downcase
      return HTTPS if normalized == HTTPS
      return HTTP if normalized == HTTP

      nil
    end
  end
end

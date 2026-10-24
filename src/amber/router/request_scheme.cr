require "../support/trusted_proxy_network"

module Amber::Router
  # Decides which scheme, `"https"` or `"http"`, a client used to reach the
  # application. `HTTP::Request#scheme` and `HTTP::Request#https?` call it,
  # and everything in Amber that asks "is this request HTTPS" (the cookie
  # jar's Secure handling, and with it the session and CSRF cookies) goes
  # through those two methods.
  #
  # The scheme starts as the connection's own: `"https"` when Amber terminates
  # TLS itself (`server.ssl` is configured), otherwise `"http"`. When the
  # immediate peer is one of the trusted proxies, the scheme that proxy
  # reported replaces it, read in this order:
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

    private FORWARDED_HEADER         = "Forwarded"
    private X_FORWARDED_PROTO_HEADER = "X-Forwarded-Proto"
    private CGI_HTTPS_HEADER         = "HTTPS"

    # Returns the scheme of *request*. *list_of_trusted_proxies* is the parsed
    # `server.trusted_proxies` setting, and *server_terminates_tls* states
    # whether Amber itself accepted the connection over TLS.
    def self.resolve(request : ::HTTP::Request,
                     list_of_trusted_proxies : Array(Amber::Support::TrustedProxyNetwork),
                     server_terminates_tls : Bool) : String
      connection_scheme = server_terminates_tls ? HTTPS : HTTP
      return connection_scheme unless peer_is_a_trusted_proxy?(request.remote_address, list_of_trusted_proxies)

      headers = request.headers
      forwarded_proto(headers) || x_forwarded_proto(headers) || cgi_https_flag(headers) || connection_scheme
    end

    # Returns `true` when *peer* falls inside one of *list_of_trusted_proxies*.
    # A request without a peer address (built in memory rather than read from
    # a socket) is never from a trusted proxy.
    def self.peer_is_a_trusted_proxy?(peer : Socket::Address?,
                                      list_of_trusted_proxies : Array(Amber::Support::TrustedProxyNetwork)) : Bool
      return false unless peer

      list_of_trusted_proxies.any?(&.includes?(peer))
    end

    # Returns the `proto=` value of the last `Forwarded` element when it names
    # http or https.
    private def self.forwarded_proto(headers : ::HTTP::Headers) : String?
      header_lines = headers.get?(FORWARDED_HEADER)
      return unless header_lines

      last_element = split_outside_quotes(header_lines.join(','), ',').last?
      return unless last_element

      split_outside_quotes(last_element, ';').each do |pair|
        parameter_name, separator, parameter_value = pair.partition('=')
        next if separator.empty?
        next unless parameter_name.strip.compare("proto", case_insensitive: true) == 0

        return known_scheme(unquoted(parameter_value.strip))
      end

      nil
    end

    # Returns the last `X-Forwarded-Proto` value when it names http or https.
    private def self.x_forwarded_proto(headers : ::HTTP::Headers) : String?
      header_lines = headers.get?(X_FORWARDED_PROTO_HEADER)
      return unless header_lines

      list_of_values = header_lines.join(',').split(',').map(&.strip).reject(&.empty?)
      last_value = list_of_values.last?
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

    private def self.unquoted(value : String) : String
      if value.size >= 2 && value.starts_with?('"') && value.ends_with?('"')
        value[1...-1]
      else
        value
      end
    end

    # Splits *text* on *separator*, leaving separators inside a quoted string
    # (RFC 7230 `quoted-string`, with backslash escapes) in place.
    private def self.split_outside_quotes(text : String, separator : Char) : Array(String)
      list_of_parts = [] of String
      current_part = String::Builder.new
      inside_quotes = false
      escaped = false

      text.each_char do |char|
        if escaped
          current_part << char
          escaped = false
        elsif inside_quotes && char == '\\'
          current_part << char
          escaped = true
        elsif char == '"'
          current_part << char
          inside_quotes = !inside_quotes
        elsif char == separator && !inside_quotes
          list_of_parts << current_part.to_s.strip
          current_part = String::Builder.new
        else
          current_part << char
        end
      end
      list_of_parts << current_part.to_s.strip

      list_of_parts.reject(&.empty?)
    end
  end
end

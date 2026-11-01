require "http"

module Amber::Router
  # :nodoc:
  #
  # Parsing shared by `RequestScheme` and `ClientAddress` for the proxy
  # headers `Forwarded` (RFC 7239) and the `X-Forwarded-*` family. Every
  # method returns hops in the order proxies appended them, nearest last.
  module ForwardedHeader
    FORWARDED = "Forwarded"

    # Returns, for each `Forwarded` element, the value of *parameter_name*
    # (unquoted), or `nil` when that element does not carry it.
    #
    # A field with an unterminated quoted string is malformed as a whole:
    # its open quote would swallow the elements proxies appended after it,
    # so it yields a single element with no value, which callers treat as an
    # unknown hop and an unknown scheme.
    def self.list_of_parameter_values(headers : ::HTTP::Headers, parameter_name : String) : Array(String?)
      header_lines = headers.get?(FORWARDED)
      return [] of String? unless header_lines

      list_of_elements = split_outside_quotes(header_lines.join(','), ',')
      return [nil] of String? unless list_of_elements

      list_of_elements.map do |element|
        parameter_value(element, parameter_name)
      end
    end

    # Returns the comma-separated values of *header_name* across all of its
    # header lines, stripped. An empty value stays in its position, so a
    # malformed hop is never skipped over to reach a value further away.
    def self.list_of_values(headers : ::HTTP::Headers, header_name : String) : Array(String)
      header_lines = headers.get?(header_name)
      return [] of String unless header_lines

      header_lines.join(',').split(',').map(&.strip)
    end

    # Returns the IP address inside a forwarded node such as `192.0.2.7`,
    # `192.0.2.7:4711`, `2001:db8::7`, or `[2001:db8::7]:4711`, or `nil` when
    # the node is not exactly one of those forms (`unknown`, an obfuscated
    # `_hidden` identifier, a malformed port, text after the address, or
    # garbage). A port may be a number up to 65535 or an RFC 7239 obfuscated
    # port such as `_8080`.
    def self.node_address(node : String) : Socket::IPAddress?
      address_text = node_host(unquoted(node.strip))
      return unless address_text

      Socket::IPAddress.new(address_text, 0)
    end

    # Returns the address part of a node when the whole node is well formed.
    private def self.node_host(text : String) : String?
      if text.starts_with?('[')
        closing = text.index(']')
        return unless closing

        port_part = text[(closing + 1)..]
        return unless port_part.empty? || (port_part.starts_with?(':') && node_port?(port_part[1..]))

        host = text[1...closing]
        Socket::IPAddress.valid_v6?(host) ? host : nil
      elsif text.count(':') == 1
        host, _separator, port = text.partition(':')
        return unless node_port?(port)

        Socket::IPAddress.valid_v4?(host) ? host : nil
      else
        # An IPv4 address without a port, or an unbracketed IPv6 address as
        # X-Forwarded-For writes it.
        Socket::IPAddress.valid?(text) ? text : nil
      end
    end

    private def self.node_port?(port : String) : Bool
      if port.starts_with?('_')
        port.size > 1 && port.each_char.skip(1).all? { |char| char.ascii_alphanumeric? || char.in?('.', '_', '-') }
      else
        port.size.in?(1..5) && port.each_char.all?(&.ascii_number?) && port.to_i <= 65_535
      end
    end

    private def self.parameter_value(element : String, parameter_name : String) : String?
      list_of_pairs = split_outside_quotes(element, ';')
      return unless list_of_pairs

      list_of_pairs.each do |pair|
        name, separator, value = pair.partition('=')
        next if separator.empty?
        next unless name.strip.compare(parameter_name, case_insensitive: true) == 0

        return unquoted(value.strip)
      end

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
    # (RFC 7230 `quoted-string`, with backslash escapes) in place. Keeps empty
    # parts so that every `Forwarded` element keeps its position. Returns
    # `nil` when a quoted string is never closed.
    private def self.split_outside_quotes(text : String, separator : Char) : Array(String)?
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
      return if inside_quotes || escaped

      list_of_parts << current_part.to_s.strip
      list_of_parts
    end
  end
end

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
    def self.list_of_parameter_values(headers : ::HTTP::Headers, parameter_name : String) : Array(String?)
      header_lines = headers.get?(FORWARDED)
      return [] of String? unless header_lines

      split_outside_quotes(header_lines.join(','), ',').map do |element|
        parameter_value(element, parameter_name)
      end
    end

    # Returns the comma-separated values of *header_name* across all of its
    # header lines, stripped, with empty values dropped.
    def self.list_of_values(headers : ::HTTP::Headers, header_name : String) : Array(String)
      header_lines = headers.get?(header_name)
      return [] of String unless header_lines

      header_lines.join(',').split(',').map(&.strip).reject(&.empty?)
    end

    # Returns the IP address inside a forwarded node such as `192.0.2.7`,
    # `192.0.2.7:4711`, `2001:db8::7`, or `[2001:db8::7]:4711`, or `nil` when
    # the node is not an IP address (`unknown`, an obfuscated `_hidden`
    # identifier, or garbage).
    def self.node_address(node : String) : Socket::IPAddress?
      text = unquoted(node.strip)
      address_text =
        if text.starts_with?('[')
          closing = text.index(']')
          return unless closing
          text[1...closing]
        elsif text.count(':') == 1
          text.partition(':').first
        else
          text
        end

      return unless Socket::IPAddress.valid?(address_text)

      Socket::IPAddress.new(address_text, 0)
    end

    private def self.parameter_value(element : String, parameter_name : String) : String?
      split_outside_quotes(element, ';').each do |pair|
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
    # parts so that every `Forwarded` element keeps its position.
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

      list_of_parts
    end
  end
end

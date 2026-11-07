require "http/cookie"

module Amber::Router::Cookies
  # Reads a request's `Cookie` header in one pass, and finds the same cookies
  # `HTTP::Cookies.from_client_headers` finds. Sessions and CSRF read cookies here,
  # and an app may read `request.cookies`, so both must agree on a repeated name.
  #
  # Pairs are separated by `; `. Text after a bare `;` is ignored up to the next `; `.
  # A pair with an invalid name or value is left out and the pairs around it still
  # count, so one malformed cookie from a client never fails a request.
  module HeaderParser
    def self.each_cookie(header : String, & : HTTP::Cookie ->) : Nil
      header.split("; ") do |segment|
        if cookie = cookie_from_segment(segment)
          yield cookie
        end
      end
    end

    private def self.cookie_from_segment(segment : String) : HTTP::Cookie?
      pair_end = segment.byte_index(';') || segment.bytesize
      separator_index = segment.byte_index('=')
      return nil if separator_index.nil? || separator_index >= pair_end

      name = segment.byte_slice(0, separator_index).strip
      return nil if name.empty?

      HTTP::Cookie.new(name, value_from(segment.byte_slice(separator_index + 1, pair_end - separator_index - 1).lstrip))
    rescue IO::Error | ArgumentError
      nil
    end

    # A whole quoted value loses its quotes. Otherwise the value is the run of cookie
    # characters at the start of the text, so an unclosed quote gives an empty value.
    private def self.value_from(text : String) : String
      if text.starts_with?('"')
        closing_quote_index = text.byte_index('"', 1)
        if closing_quote_index
          quoted_value = text.byte_slice(1, closing_quote_index - 1)
          return quoted_value if quoted_value.each_byte.all? { |byte| cookie_character?(byte) }
        end

        return ""
      end

      value_end = text.to_slice.index { |byte| !cookie_character?(byte) } || text.bytesize
      text.byte_slice(0, value_end).strip
    end

    # RFC 6265 cookie-octets plus the space the standard library also accepts:
    # printable ASCII except `"`, `,`, `;` and `\`.
    private def self.cookie_character?(byte : UInt8) : Bool
      byte.in?(0x20_u8..0x7E_u8) && !(byte === '"' || byte === ',' || byte === ';' || byte === '\\')
    end
  end
end

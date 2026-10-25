module Amber::Router::Parsers
  module FormData
    # Parses a URL-encoded request body, checking each pair as it streams
    # and charging *budget* (the request's own budget by default).
    #
    # A `charset` declared in the `Content-Type` is decoded to UTF-8 while
    # the body streams, as `HTTP::Request#form_params` does in Crystal.
    def self.parse(request : HTTP::Request, budget : ParamBudget = request.param_budget) : HTTP::Params
      body = request.body
      return HTTP::Params.new unless body

      charset = declared_charset(request)
      return budget.parse_form(body) unless charset

      begin
        # The raw bytes are bounded too, so an encoding that shrinks when
        # decoded (such as UTF-16) cannot carry more than the limit.
        max_form_body_bytes = budget.limits.max_form_body_bytes.to_i64
        raw_body = BoundedIO.new(body, max_form_body_bytes, "max_form_body_bytes")
        raw_body.set_encoding(charset)
        budget.parse_form(UTF8Reader.new(raw_body))
      rescue ArgumentError
        # The message leaves out the client's charset and decoder text.
        raise Amber::Exceptions::BadRequest.new("The form body could not be decoded with its declared charset")
      end
    end

    private def self.declared_charset(request : HTTP::Request) : String?
      content_type = request.headers["Content-Type"]?
      return unless content_type
      media_type = MIME::MediaType.parse?(content_type)
      return unless media_type
      media_type["charset"]?
    end

    # Reads *io* as UTF-8, decoding the encoding set on it.
    private class UTF8Reader < IO
      def initialize(@io : IO)
      end

      def read(slice : Bytes) : Int32
        @io.read_utf8(slice)
      end

      def write(slice : Bytes) : Nil
        raise IO::Error.new("UTF8Reader is read-only")
      end
    end

    def self.parse_part(input : IO, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : HTTP::Params
      ParamBudget.new(limits).parse_form(input)
    end

    def self.parse_part(input : String, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : HTTP::Params
      parse_part(IO::Memory.new(input), limits)
    end

    def self.parse_part(input : Nil, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : HTTP::Params
      HTTP::Params.new
    end
  end
end

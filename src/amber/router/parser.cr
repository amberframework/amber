require "./parsers/**"

module Amber::Router
  module Parser
    TYPE_EXT_REGEX   = Amber::Support::MimeTypes::TYPE_EXT_REGEX
    URL_ENCODED_FORM = "application/x-www-form-urlencoded"
    MULTIPART_FORM   = "multipart/form-data"
    APPLICATION_JSON = "application/json"
    @parsed = false

    def params
      return @params if @parsed
      parse_url_params
      form_data
      json
      multipart
      @parsed = true
      @params
    end

    private def parse_url_params
      query_params.each do |k, v|
        @params.store.add(k, v)
      end
    end

    private def form_data
      return unless content_type.try &.starts_with? URL_ENCODED_FORM
      Parsers::FormData.parse(self).each do |k, v|
        @params.store.add(k, v)
      end
    end

    private def multipart
      return unless content_type.try &.starts_with? MULTIPART_FORM
      Parsers::Multipart.parse(@params, self)
    end

    private def json
      return unless content_type.try &.starts_with? APPLICATION_JSON
      Parsers::JSON.parse(@params.store, self)
    end

    private def content_type
      headers["Content-Type"]?
    end
  end
end

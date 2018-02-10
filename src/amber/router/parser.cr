require "http"
require "./params"
require "./file"
require "./parsers/**"

module Amber::Router
  class Parser
    TYPE_EXT_REGEX   = Amber::Support::MimeTypes::TYPE_EXT_REGEX
    URL_ENCODED_FORM = "application/x-www-form-urlencoded"
    MULTIPART_FORM   = "multipart/form-data"
    APPLICATION_JSON = "application/json"
    @parsed = false
    @request : HTTP::Request
    @params : Amber::Router::Params = Amber::Router::Params.new

    def self.params(request : HTTP::Request)
      new(request).params
    end

    def initialize(@request)
    end

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
      @request.query_params.each do |k, v|
        @params.store.add(k, v)
      end
    end

    private def form_data
      return unless content_type.try &.starts_with? URL_ENCODED_FORM
      Parsers::FormData.parse(@request).each do |k, v|
        @params.store.add(k, v)
      end
    end

    private def multipart
      return unless content_type.try &.starts_with? MULTIPART_FORM
      Parsers::Multipart.parse(@params, @request)
    end

    private def json
      return unless content_type.try &.starts_with? APPLICATION_JSON
      Parsers::JSON.parse(@params.store, @request)
    end

    private def content_type
      @request.headers["Content-Type"]?
    end
  end
end

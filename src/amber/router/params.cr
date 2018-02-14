require "http"
require "./parsers/*"
require "./file"

module Amber::Router
  module Types
    alias Key = String | Symbol
    alias Files = Hash(String, Amber::Router::File)
    alias Params = Hash(String, String)
  end

  class Params
    TYPE_EXT_REGEX   = Amber::Support::MimeTypes::TYPE_EXT_REGEX
    URL_ENCODED_FORM = "application/x-www-form-urlencoded"
    MULTIPART_FORM   = "multipart/form-data"
    APPLICATION_JSON = "application/json"

    getter empty = Types::Params.new

    @files = Types::Files.new
    @multipart : Types::Params?
    @json : Types::Params?
    @form : HTTP::Params?

    def initialize(@request : HTTP::Request)
    end

    def [](key : Types::Key) : String
      self.[key]? || raise Amber::Exceptions::Validator::InvalidParam.new(key)
    end

    def []?(key : Types::Key)
      _key = key.to_s
      route[_key]? || override_method?(_key) || json[_key]?
    end

    def files
      multipart
      @files
    end

    def []=(key : Types::Key, value)
      query[key.to_s] = value
    end

    def key?(key : Types::Key)
      self.[key.to_s]?
    end

    def fetch_all(key : Types::Key) : Array
      _key = key.to_s
      query.fetch_all(_key) || form.fetch_all(_key)
    end

    def json(key : Types::Key)
      JSON.parse(self[key]?.to_s)
    rescue JSON::ParseException
      raise "Value of params.json(#{key.inspect}) is not JSON!"
    end

    def override_method?(key : Types::Key)
      query[key]? || form[key]? || multipart[key]?
    end

    def to_h
      {
        :multipart => multipart.to_h,
        :json      => json.to_h,
        :route     => route.to_h,
        :form      => form.to_h,
        :query     => query.to_h,
      }
    end

    private def query
      @request.query_params
    end

    private def form
      return HTTP::Params.parse("") unless content_type?(URL_ENCODED_FORM)
      @form ||= Parsers::FormData.parse(@request)
    end

    private def multipart
      return @multipart.not_nil! if @multipart
      return empty unless content_type?(MULTIPART_FORM)
      @multipart, @files = Parsers::Multipart.parse(@request)
      @multipart.not_nil!
    end

    private def json
      return empty unless content_type?(APPLICATION_JSON)
      @json ||= Parsers::JSON.parse(@request)
    end

    private def route
      @request.matched_route.params
    end

    private def content_type?(header_type)
      @request.headers["Content-Type"]?.try &.starts_with?(header_type)
    end
  end
end

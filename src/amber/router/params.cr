require "http"
require "./parsers/*"
require "./file"

module Amber::Router
  module Types
    alias Key = String | Symbol
    alias File = Hash(String, Amber::Router::File)
    alias Files = Hash(String, Array(Amber::Router::File))
    alias UploadFile = File | Files
    alias Params = Hash(String, String)
  end

  class Params
    TYPE_EXT_REGEX   = Amber::Support::MimeTypes::TYPE_EXT_REGEX
    URL_ENCODED_FORM = "application/x-www-form-urlencoded"
    MULTIPART_FORM   = "multipart/form-data"
    APPLICATION_JSON = "application/json"

    @files : Types::UploadFile?
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
      multipart unless @multipart
      @files ? @files.not_nil! : Types::Params.new
    end

    def []=(key : Types::Key, value)
      query[key.to_s] = value
    end

    def has_key?(key : Types::Key) : Bool
      !!self.[key.to_s]?
    end

    def fetch_all(key : Types::Key) : Array
      _key = key.to_s
      if query.has_key?(_key)
        query.fetch_all(_key)
      else
        form.fetch_all(_key)
      end
    end

    def json(key : Types::Key)
      JSON.parse(self[key]?.to_s)
    rescue JSON::ParseException
      raise "Value of params.json(#{key.inspect}) is not JSON!"
    end

    def override_method?(key : Types::Key)
      query[key]? || form[key]? || multipart[key]?
    end

    def to_h : Types::Params
      params_hash = Types::Params.new
      query.each { |key, _| params_hash[key] = query[key] }
      form.each { |key, _| params_hash[key] = form[key] }

      route.each_key do |key|
        if value = route[key]
          params_hash[key] = value
        end
      end

      json.each_key { |key| params_hash[key] = json[key].to_s }
      multipart.each_key { |key| params_hash[key] = multipart[key].to_s }
      params_hash
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
      return Types::Params.new unless content_type?(MULTIPART_FORM)
      @multipart, @files = Parsers::Multipart.parse(@request)
      @multipart.not_nil!
    end

    private def json
      return Types::Params.new unless content_type?(APPLICATION_JSON)
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

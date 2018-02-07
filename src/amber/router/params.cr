module Amber::Router
  struct File
    getter file : Tempfile
    getter filename : String?
    getter headers : HTTP::Headers
    getter creation_time : Time?
    getter modification_time : Time?
    getter read_time : Time?
    getter size : UInt64?

    def initialize(upload)
      @filename = upload.filename
      @file = Tempfile.new(filename)
      ::File.open(@file.path, "w") do |f|
        ::IO.copy(upload.body, f)
      end
      @headers = upload.headers
      @creation_time = upload.creation_time
      @modification_time = upload.modification_time
      @read_time = upload.read_time
      @size = upload.size
    end
  end

  struct Params
    property files = {} of String => File
    property store : HTTP::Params = HTTP::Params.new( Hash(String, Array(String)).new)

    forward_missing_to @store

    def initialize
    end

    def initialize(@store)
    end

    def json(key)
      JSON.parse(store[key]?.to_s)
    rescue JSON::ParseException
      raise "Value of params.json(#{key.inspect}) is not JSON!"
    end
  end

  module Parse
    TYPE_EXT_REGEX = Amber::Support::MimeTypes::TYPE_EXT_REGEX
    URL_ENCODED_FORM = "application/x-www-form-urlencoded"
    MULTIPART_FORM = "multipart/form-data"
    APPLICATION_JSON = "application/json"

    def params
      @params.store = query_params
      form_data(self, @params)
      json(self, @params)
      multipart(self, @params)
      @params
    end

    private def form_data(request, params)
      return unless content_type.try &.starts_with? URL_ENCODED_FORM
      Parser::FormData.parse(request).each do |k, v|
        params.store.add(k, v)
      end
    end

    private def multipart(request, params)
      return unless content_type.try &.starts_with? MULTIPART_FORM
      Parser::Multipart.parse(@params, request)
    end

    private def json(request, params)
      return unless content_type.try &.starts_with? APPLICATION_JSON
      Parser::JSON.parse(params.store, request)
    end

    private def content_type
      headers["Content-Type"]?
    end
  end
end

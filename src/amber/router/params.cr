struct HTTP::Params
  getter raw_params
end

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

  class Params < Hash(String, Array(String) | String)
    alias KeyType = String | Symbol
    property files = {} of String => File

    def json(key : KeyType)
      JSON.parse(self[key]?.to_s)
    rescue JSON::ParseException
      raise "Value of params.json(#{key.inspect}) is not JSON!"
    end

    def [](key : KeyType)
      val = fetch(key)
      case val
      when Array  then val.as(Array).first
      when String then val
      end
    end

    def fetch_all(key : KeyType)
      fetch(key)
    end

    def []=(key : KeyType, value : V)
      super(key, value)
    end

    def find_entry(key : KeyType)
      super(key)
    end
  end

  class Parse
    URL_ENCODED_FORM = "application/x-www-form-urlencoded"

    getter request : HTTP::Request
    getter params = Params.new
    def initialize(@request : HTTP::Request)
    end

    def parse
      query_params
      form_data
      params
    end

    private def query_params
      params.merge! request.query_params.raw_params
    end

    private def form_data
      return unless content_type.try &.starts_with? URL_ENCODED_FORM
      params.merge! Parser::FormData.new(request).parse.raw_params
    end

    private def content_type
      @request.headers["Content-Type"]?
    end
  end
end
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
    Log = ::Log.for(self)

    TYPE_EXT_REGEX   = Amber::Support::MimeTypes::TYPE_EXT_REGEX
    URL_ENCODED_FORM = "application/x-www-form-urlencoded"
    MULTIPART_FORM   = "multipart/form-data"
    APPLICATION_JSON = "application/json"

    @files : Types::Files?
    @multipart : Types::Params?
    @json : Types::Params?
    @form : HTTP::Params?

    # Tempfile holding the raw multipart body so it can be replayed to the
    # controller. Deleted by #cleanup_uploads at request teardown.
    @body_spool : ::File?

    def initialize(@request : HTTP::Request)
    end

    def [](key : Types::Key) : String
      self.[key]? || raise Amber::Exceptions::Validator::InvalidParam.new(key)
    end

    def []?(key : Types::Key)
      _key = key.to_s
      route[_key]? || override_method?(_key) || json_value?(_key)
    end

    def files
      multipart unless @multipart
      @files ||= Types::Files.new
    end

    # Returns parsed URL-encoded form parameters, reusing the cached body parse.
    # Schema request parsing uses this after routing has inspected `_method`.
    def form_params : HTTP::Params
      form
    end

    # Returns parsed multipart fields, reusing the cached body parse.
    def multipart_params : Types::Params
      multipart
    end

    # Delete every tempfile this request spooled: the uploaded files themselves,
    # and the spool holding the raw multipart body when one was made.
    #
    # Deliberately reads only ALREADY-parsed state. It must never call #files or
    # #multipart, which would trigger a parse during teardown — on a request
    # whose body has since been consumed that would raise.
    #
    # Best effort throughout: teardown must never raise into the request cycle.
    def cleanup_uploads : Nil
      if uploaded_files = @files
        uploaded_files.each_value(&.cleanup)
        uploaded_files.clear
      end

      if spool = @body_spool
        @body_spool = nil
        release_body_spool(spool)
      end
    end

    private def release_body_spool(spool : ::File) : Nil
      spool.close
      ::File.delete?(spool.path)
    rescue error : IO::Error
      Log.warn(exception: error) { "Could not delete the multipart body spool #{spool.path}" }
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
      _key = key.to_s
      query[_key]? || form_value?(_key) || multipart_value?(_key)
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

    private def form_value?(key : String) : String?
      return unless content_type?(URL_ENCODED_FORM)
      (@form ||= Parsers::FormData.parse(@request))[key]?
    end

    private def multipart
      return @multipart.not_nil! if @multipart
      return Types::Params.new unless content_type?(MULTIPART_FORM)
      @multipart, @files, @body_spool = Parsers::Multipart.parse(@request)
      @multipart.not_nil!
    end

    private def multipart_value?(key : String) : String?
      return unless content_type?(MULTIPART_FORM)
      multipart[key]?
    end

    private def json
      return Types::Params.new unless content_type?(APPLICATION_JSON)
      @json ||= Parsers::JSON.parse(@request)
    end

    private def json_value?(key : String) : String?
      return unless content_type?(APPLICATION_JSON)
      json[key]?
    end

    private def route
      @request.matched_route.params
    end

    private def content_type?(header_type)
      @request.headers["Content-Type"]?.try &.starts_with?(header_type)
    end
  end
end

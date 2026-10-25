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

    @files : Types::Files?
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
      route[_key]? || override_method?(_key) || json_value?(_key)
    end

    def files
      multipart unless @multipart
      @files ||= Types::Files.new
    end

    # Deletes the tempfiles behind `files`, if the body was parsed. A file
    # that cannot be deleted is logged and kept for
    # `Amber::Router::File.retry_leftover_deletions`, so the rest are still
    # removed and the request's own error, if any, is kept.
    def delete_uploaded_files : Nil
      if uploaded_files = @files
        uploaded_files.each_value do |uploaded_file|
          uploaded_file.delete_tempfile
        rescue ex : IO::Error
          Amber::Router::File::Log.warn(exception: ex) { "Could not delete the upload tempfile #{uploaded_file.path}; retrying later" }
          uploaded_file.defer_deletion
        end
      end
    end

    # Returns parsed URL-encoded form parameters, reusing the cached body parse.
    # Schema request parsing uses this after routing has inspected `_method`.
    def form_params : HTTP::Params
      form
    end

    # Whether the request body is URL-encoded form data.
    def url_encoded_form? : Bool
      !!content_type?(URL_ENCODED_FORM)
    end

    # Returns parsed multipart fields, reusing the cached body parse.
    def multipart_params : Types::Params
      multipart
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

    private def form : HTTP::Params
      return HTTP::Params.parse("") unless content_type?(URL_ENCODED_FORM)
      @request.raise_body_rejection!
      if parsed = @form
        return parsed
      end
      @form = parse_body { Parsers::FormData.parse(@request) }
    end

    private def form_value?(key : String) : String?
      return unless content_type?(URL_ENCODED_FORM)
      form[key]?
    end

    private def multipart : Types::Params
      @request.raise_body_rejection!
      if parsed = @multipart
        return parsed
      end
      return Types::Params.new unless content_type?(MULTIPART_FORM)

      fields, @files = parse_body { Parsers::Multipart.parse(@request) }
      @multipart = fields
    end

    private def multipart_value?(key : String) : String?
      return unless content_type?(MULTIPART_FORM)
      multipart[key]?
    end

    private def json : Types::Params
      return Types::Params.new unless content_type?(APPLICATION_JSON)
      @request.raise_body_rejection!
      if parsed = @json
        return parsed
      end
      @json = parse_body { Parsers::JSON.parse(@request) }
    end

    # Parses the body through `HTTP::Request#guard_body_read`, so a rejected
    # body is rejected again on every later read.
    private def parse_body(& : -> T) : T forall T
      @request.guard_body_read { yield }
    end

    private def json_value?(key : String) : String?
      return unless content_type?(APPLICATION_JSON)
      json[key]?
    end

    private def route
      @request.matched_route.params
    end

    # Whether *content_type*'s media type, the part before any `;`
    # parameters, is *expected*, compared without regard to letter case.
    # `Application/X-WWW-Form-Urlencoded; charset=utf-8` is a URL-encoded
    # form; `application/x-www-form-urlencodedx` is not.
    def self.media_type?(content_type : String?, expected : String) : Bool
      return false unless content_type
      media_type_end = content_type.byte_index(';') || content_type.bytesize
      media_type = content_type.byte_slice(0, media_type_end).strip
      media_type.compare(expected, case_insensitive: true) == 0
    end

    private def content_type?(header_type : String) : Bool
      content_type = @request.headers["Content-Type"]?
      if header_type == APPLICATION_JSON
        # JSON keeps its prefix match, as before this change.
        return false unless content_type
        return content_type.starts_with?(header_type)
      end

      self.class.media_type?(content_type, header_type)
    end
  end
end

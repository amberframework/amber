# Base parser module for transforming and coercing data

module Amber::Schema
  module Parser
    # Base class for all parsers
    abstract class Base
      abstract def parse(value : JSON::Any) : JSON::Any
      abstract def can_parse?(value : JSON::Any) : Bool
    end

    # Registry for content-type based parser selection
    class ParserRegistry
      class_property parsers = {} of String => String

      # Register a parser for a content type
      def self.register(content_type : String, parser_name : String)
        parsers[normalize_content_type(content_type)] = parser_name
      end

      # Get parser name for content type
      def self.get(content_type : String?) : String?
        return nil unless content_type
        normalized = normalize_content_type(content_type)
        parsers[normalized]?
      end

      # Parse request based on content type
      def self.parse_request(request : HTTP::Request) : Hash(String, JSON::Any)
        content_type = request.headers["Content-Type"]?
        parser_name = get(content_type)

        case parser_name
        when "json"
          parse_json_request(request)
        when "query"
          parse_query_request(request)
        when "xml"
          parse_xml_request(request)
        else
          # Try to detect format from content
          body = request.body.try(&.gets_to_end) || ""
          if body.starts_with?("{") || body.starts_with?("[")
            parse_json_body(body)
          elsif body.starts_with?("<")
            parse_xml_body(body)
          else
            {} of String => JSON::Any
          end
        end
      rescue ex
        raise SchemaDefinitionError.new("Failed to parse request: #{ex.message}")
      end

      # Parse JSON request
      private def self.parse_json_request(request : HTTP::Request) : Hash(String, JSON::Any)
        body = request.body.try(&.gets_to_end) || ""
        parse_json_body(body)
      end

      # Parse JSON body string
      private def self.parse_json_body(body : String) : Hash(String, JSON::Any)
        JSONParser.parse_string(body)
      end

      # Parse query string request
      private def self.parse_query_request(request : HTTP::Request) : Hash(String, JSON::Any)
        content_type = request.headers["Content-Type"]?

        if content_type && content_type.starts_with?("multipart/form-data")
          # Handle multipart form data with files
          MultipartParser.parse_multipart_request(request)
        elsif content_type && content_type.starts_with?("application/x-www-form-urlencoded")
          # Handle URL-encoded form data
          body = request.body.try(&.gets_to_end) || ""
          if body.empty?
            {} of String => JSON::Any
          else
            params = HTTP::Params.parse(body)
            QueryParser.parse_params_to_nested(params)
          end
        else
          # Default to query parameters
          QueryParser.parse_params_to_nested(request.query_params)
        end
      end

      # Parse XML request
      private def self.parse_xml_request(request : HTTP::Request) : Hash(String, JSON::Any)
        body = request.body.try(&.gets_to_end) || ""
        parse_xml_body(body)
      end

      # Parse XML body string
      private def self.parse_xml_body(body : String) : Hash(String, JSON::Any)
        XMLParser.parse_string(body)
      end

      # Normalize content type (remove charset, etc)
      private def self.normalize_content_type(content_type : String) : String
        # Extract just the media type part
        parts = content_type.split(';')
        parts.first.strip.downcase
      end
    end

    # Default parser registrations
    ParserRegistry.register("application/json", "json")
    ParserRegistry.register("text/json", "json")
    ParserRegistry.register("application/x-www-form-urlencoded", "query")
    ParserRegistry.register("multipart/form-data", "query")
    ParserRegistry.register("application/xml", "xml")
    ParserRegistry.register("text/xml", "xml")
    ParserRegistry.register("application/xhtml+xml", "xml")

    # Parser context with access to full data and schema
    class Context
      getter data : Hash(String, JSON::Any)
      getter schema : Definition
      getter errors : Array(Error) = [] of Error

      def initialize(@data : Hash(String, JSON::Any), @schema : Definition)
      end

      def add_error(error : Error)
        @errors << error
      end

      def has_errors?
        !@errors.empty?
      end
    end

    # Type coercion parser
    class TypeCoercion < Base
      def initialize(@target_type : T.class) forall T
      end

      def parse(value : JSON::Any) : JSON::Any
        case @target_type
        when String.class
          parse_string(value)
        when Int32.class, Int64.class
          parse_integer(value)
        when Float32.class, Float64.class
          parse_float(value)
        when Bool.class
          parse_boolean(value)
        when Time.class
          parse_time(value)
        when Array.class
          parse_array(value)
        when Hash.class
          parse_hash(value)
        else
          value
        end
      end

      def can_parse?(value : JSON::Any) : Bool
        true # Type coercion always attempts to parse
      end

      private def parse_string(value : JSON::Any) : JSON::Any
        case value.raw
        when String
          value
        when Number
          JSON::Any.new(value.raw.to_s)
        when Bool
          JSON::Any.new(value.raw.to_s)
        else
          value
        end
      end

      private def parse_integer(value : JSON::Any) : JSON::Any
        case value.raw
        when Int
          value
        when Float
          JSON::Any.new(value.raw.to_i64)
        when String
          if parsed = value.as_s.to_i64?
            JSON::Any.new(parsed)
          else
            value
          end
        else
          value
        end
      end

      private def parse_float(value : JSON::Any) : JSON::Any
        case value.raw
        when Number
          JSON::Any.new(value.raw.to_f64)
        when String
          if parsed = value.as_s.to_f64?
            JSON::Any.new(parsed)
          else
            value
          end
        else
          value
        end
      end

      private def parse_boolean(value : JSON::Any) : JSON::Any
        case value.raw
        when Bool
          value
        when String
          case value.as_s.downcase
          when "true", "1", "yes", "on"
            JSON::Any.new(true)
          when "false", "0", "no", "off"
            JSON::Any.new(false)
          else
            value
          end
        when Number
          JSON::Any.new(value.raw != 0)
        else
          value
        end
      end

      private def parse_time(value : JSON::Any) : JSON::Any
        case value.raw
        when String
          if parsed = Time.parse_iso8601(value.as_s)
            JSON::Any.new(parsed.to_s)
          else
            value
          end
        else
          value
        end
      rescue
        value
      end

      private def parse_array(value : JSON::Any) : JSON::Any
        case value.raw
        when Array
          value
        when String
          # Try to parse JSON array
          if value.as_s.starts_with?("[") && value.as_s.ends_with?("]")
            JSON.parse(value.as_s)
          else
            # Convert comma-separated values to array
            items = value.as_s.split(",").map(&.strip)
            JSON::Any.new(items.map { |item| JSON::Any.new(item) })
          end
        else
          JSON::Any.new([value])
        end
      rescue
        value
      end

      private def parse_hash(value : JSON::Any) : JSON::Any
        case value.raw
        when Hash
          value
        when String
          # Try to parse JSON object
          if value.as_s.starts_with?("{") && value.as_s.ends_with?("}")
            JSON.parse(value.as_s)
          else
            value
          end
        else
          value
        end
      rescue
        value
      end
    end

    # Transformation parser that applies custom transformations
    class Transform < Base
      def initialize(&@block : JSON::Any -> JSON::Any)
      end

      def parse(value : JSON::Any) : JSON::Any
        @block.call(value)
      end

      def can_parse?(value : JSON::Any) : Bool
        true
      end
    end

    # Chain multiple parsers together
    class Chain < Base
      getter parsers : Array(Base) = [] of Base

      def initialize(@parsers : Array(Base))
      end

      def parse(value : JSON::Any) : JSON::Any
        @parsers.reduce(value) do |current_value, parser|
          if parser.can_parse?(current_value)
            parser.parse(current_value)
          else
            current_value
          end
        end
      end

      def can_parse?(value : JSON::Any) : Bool
        @parsers.any? { |parser| parser.can_parse?(value) }
      end
    end
  end
end

require "./parsers/multipart_parser"
require "./parsers/xml_parser"

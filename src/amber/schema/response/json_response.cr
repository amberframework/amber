# JSON response formatter for Schema API
module Amber::Schema::ResponseFormatters
  class JSONResponse
    # Response structure options
    enum Structure
      Simple   # Just data or error
      Envelope # Wrapped in standard envelope
      JSONAPI  # JSON:API specification format
    end

    getter structure : Structure
    getter pretty : Bool
    getter include_metadata : Bool

    def initialize(
      @structure : Structure = Structure::Envelope,
      @pretty : Bool = false,
      @include_metadata : Bool = true,
    )
    end

    # Format a response builder into JSON
    def format(builder : ResponseBuilder) : String
      response = case @structure
                 when Structure::Simple
                   format_simple(builder)
                 when Structure::Envelope
                   format_envelope(builder)
                 when Structure::JSONAPI
                   format_jsonapi(builder)
                 else
                   builder.build
                 end

      @pretty ? response.to_pretty_json : response.to_json
    end

    # Format validation result into JSON
    def format_result(result : Result) : String
      builder = ResponseBuilder.from_result(result)
      format(builder)
    end

    private def format_simple(builder : ResponseBuilder) : Hash(String, JSON::Any)
      if builder.status == ResponseBuilder::Status::Success
        builder.data || {} of String => JSON::Any
      else
        {
          "errors" => JSON::Any.new(builder.errors.map { |e| JSON::Any.new(e.to_h) }),
        }
      end
    end

    private def format_envelope(builder : ResponseBuilder) : Hash(String, JSON::Any)
      response = builder.build

      # Remove metadata if not wanted
      response.delete("meta") unless @include_metadata
      response.delete("timestamp") unless @include_metadata

      response
    end

    private def format_jsonapi(builder : ResponseBuilder) : Hash(String, JSON::Any)
      response = {
        "jsonapi" => JSON::Any.new({"version" => JSON::Any.new("1.0")}),
      } of String => JSON::Any

      if builder.data
        response["data"] = JSON::Any.new(builder.data)
      end

      if !builder.errors.empty?
        response["errors"] = JSON::Any.new(
          builder.errors.map do |error|
            JSON::Any.new({
              "status" => JSON::Any.new("422"),
              "source" => JSON::Any.new({"pointer" => JSON::Any.new("/data/attributes/#{error.field}")}),
              "title"  => JSON::Any.new(error.code),
              "detail" => JSON::Any.new(error.message),
            })
          end
        )
      end

      if @include_metadata && !builder.metadata.empty?
        response["meta"] = JSON::Any.new(builder.metadata)
      end

      response
    end

    # Helper to create standard error responses
    def error_response(status : Int32, message : String, code : String? = nil) : String
      builder = ResponseBuilder.error(message, code || "error")

      # Add HTTP status to metadata
      builder.add_metadata("http_status", JSON::Any.new(status.to_i64))

      format(builder)
    end

    # Standard HTTP error responses
    def bad_request(message : String = "Bad Request") : String
      error_response(400, message, "bad_request")
    end

    def unauthorized(message : String = "Unauthorized") : String
      error_response(401, message, "unauthorized")
    end

    def forbidden(message : String = "Forbidden") : String
      error_response(403, message, "forbidden")
    end

    def not_found(message : String = "Not Found") : String
      error_response(404, message, "not_found")
    end

    def unprocessable_entity(errors : Array(Error)) : String
      builder = ResponseBuilder.validation_error(errors)
      format(builder)
    end

    def internal_server_error(message : String = "Internal Server Error") : String
      error_response(500, message, "internal_server_error")
    end
  end
end

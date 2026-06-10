# Response builder for creating standardized API responses
module Amber::Schema
  class ResponseBuilder
    # Response format options
    enum Format
      JSON
      XML # Future support
    end

    # Response status
    enum Status
      Success
      Error
      PartialSuccess
    end

    getter status : Status
    getter data : Hash(String, JSON::Any)?
    getter errors : Array(Error)
    getter warnings : Array(Warning)
    getter metadata : Hash(String, JSON::Any)

    def initialize(@status : Status = Status::Success)
      @errors = [] of Error
      @warnings = [] of Warning
      @metadata = {} of String => JSON::Any
    end

    # Build response from a validation result
    def self.from_result(result : LegacyResult) : ResponseBuilder
      builder = new(result.success? ? Status::Success : Status::Error)
      builder.data = result.data if result.data
      builder.errors.concat(result.errors)
      builder.warnings.concat(result.warnings)
      builder
    end

    # Setters with method chaining
    def data=(@data : Hash(String, JSON::Any)?)
      self
    end

    def add_error(error : Error)
      @errors << error
      @status = Status::Error if @status == Status::Success
      self
    end

    def add_warning(warning : Warning)
      @warnings << warning
      self
    end

    def add_metadata(key : String, value : JSON::Any)
      @metadata[key] = value
      self
    end

    # Set pagination metadata
    def paginate(page : Int32, per_page : Int32, total : Int32)
      add_metadata("pagination", JSON::Any.new({
        "page"        => JSON::Any.new(page.to_i64),
        "per_page"    => JSON::Any.new(per_page.to_i64),
        "total"       => JSON::Any.new(total.to_i64),
        "total_pages" => JSON::Any.new(((total.to_f / per_page).ceil).to_i64),
      }))
    end

    # Build the response
    def build(format : Format = Format::JSON) : Hash(String, JSON::Any)
      response = {
        "status"  => JSON::Any.new(@status.to_s.downcase),
        "success" => JSON::Any.new(@status != Status::Error),
      } of String => JSON::Any

      response["data"] = JSON::Any.new(@data) if @data

      if !@errors.empty?
        response["errors"] = JSON::Any.new(@errors.map { |e| JSON::Any.new(e.to_h) })
      end

      if !@warnings.empty?
        response["warnings"] = JSON::Any.new(@warnings.map { |w| JSON::Any.new(w.to_h) })
      end

      if !@metadata.empty?
        response["meta"] = JSON::Any.new(@metadata)
      end

      response["timestamp"] = JSON::Any.new(Time.utc.to_s)

      response
    end

    # Convert to JSON string
    def to_json(format : Format = Format::JSON) : String
      build(format).to_json
    end

    # HTTP status code based on response status
    def http_status : Int32
      case @status
      when Status::Success
        200
      when Status::PartialSuccess
        206
      when Status::Error
        has_validation_errors? ? 422 : 400
      end
    end

    private def has_validation_errors? : Bool
      @errors.any? { |e| e.is_a?(ValidationError) }
    end

    # Factory methods for common responses
    def self.success(data : Hash(String, JSON::Any)? = nil) : ResponseBuilder
      builder = new(Status::Success)
      builder.data = data if data
      builder
    end

    def self.error(message : String, code : String = "error") : ResponseBuilder
      builder = new(Status::Error)
      builder.add_error(Error.new("", message, code))
      builder
    end

    def self.validation_error(errors : Array(Error)) : ResponseBuilder
      builder = new(Status::Error)
      errors.each { |error| builder.add_error(error) }
      builder
    end

    def self.not_found(resource : String? = nil) : ResponseBuilder
      message = resource ? "#{resource} not found" : "Resource not found"
      error(message, "not_found")
    end

    def self.unauthorized(message : String = "Unauthorized") : ResponseBuilder
      error(message, "unauthorized")
    end

    def self.forbidden(message : String = "Forbidden") : ResponseBuilder
      error(message, "forbidden")
    end
  end
end

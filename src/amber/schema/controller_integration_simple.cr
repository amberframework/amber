# Simplified integration with Amber controllers
module Amber::Schema
  # Mixin for controllers to add schema validation
  module ControllerIntegration
    macro included
      # Instance property to store validated request data
      property request_data : Hash(String, JSON::Any)? = nil

      # Store validation result
      property validation_result : Amber::Schema::LegacyResult? = nil

      # The typed, request-local schema instance. Its class-level field metadata
      # is compiled once and shared safely; its data and errors are never shared
      # between concurrent requests.
      property validated_schema : Amber::Schema::Definition? = nil

      @schema_action : String? = nil
    end

    # Bind a reusable schema class to a controller action:
    #
    #   schema :create, CreateUserSchema
    #
    # Or define an action-local schema with the same field DSL:
    #
    #   schema :create do
    #     field :email, String, required: true, format: "email"
    #   end
    macro schema(action, schema_class = nil, &block)
      {% action_name = action.id.stringify %}
      {% generated_name = "AmberRequestSchema_#{action.id}".id %}

      {% if schema_class %}
        {% bound_schema = schema_class %}
      {% else %}
        class {{generated_name}} < ::Amber::Schema::Definition
          {{block.body}}
        end
        {% bound_schema = generated_name %}
      {% end %}

      {{"@@amber_request_schema_#{action.id}".id}} =
        ::Amber::Schema::Registry.register_request(
          {{@type.name.stringify}},
          {{action_name}},
          {{bound_schema}}
        )
    end

    # Response schemas use the same contract and are enforced before a response
    # is serialized.
    macro response_schema(action, schema_class = nil, status = 200, description = "Successful response", &block)
      {% action_name = action.id.stringify %}
      {% generated_name = "AmberResponseSchema_#{action.id}".id %}

      {% if schema_class %}
        {% bound_schema = schema_class %}
      {% else %}
        class {{generated_name}} < ::Amber::Schema::Definition
          {{block.body}}
        end
        {% bound_schema = generated_name %}
      {% end %}

      {{"@@amber_response_schema_#{action.id}".id}} =
        ::Amber::Schema::Registry.register_response(
          {{@type.name.stringify}},
          {{action_name}},
          {{bound_schema}},
          {{status}},
          {{description}}
        )
    end

    # Validate request against schema
    def validate_request(schema_name : String? = nil) : Amber::Schema::LegacyResult
      action = (schema_name || action_name).to_s
      schema_entry = Amber::Schema::Registry.request_schema(self.class.name, action)
      return Amber::Schema::LegacyResult.success(merge_request_data) unless schema_entry

      enforce_schema_content_type!(schema_entry.schema_class)

      data = merge_request_data(schema_entry.schema_class)
      schema = schema_entry.factory.call(data)
      result = schema.validate
      @validated_schema = schema
      result
    rescue ex : Amber::Schema::RequestParseError
      Amber::Schema::LegacyResult.failure([ex] of Amber::Schema::Error)
    rescue ex : Amber::Schema::SchemaDefinitionError
      error = Amber::Schema::RequestParseError.new(ex.message || "Unable to parse request body")
      Amber::Schema::LegacyResult.failure([error] of Amber::Schema::Error)
    end

    # Validate response against schema
    def validate_response(data : Hash(String, JSON::Any), status : Int32 = 200, schema_name : String? = nil) : Amber::Schema::LegacyResult
      action = (schema_name || @schema_action || action_name).to_s
      schema_entry = Amber::Schema::Registry.response_schema(self.class.name, action)
      return Amber::Schema::LegacyResult.success(data) unless schema_entry

      if status != schema_entry.status
        return Amber::Schema::LegacyResult.failure([
          Amber::Schema::CustomValidationError.new(
            "response.status",
            "Response status #{status} does not match declared status #{schema_entry.status}",
            "response_status_mismatch"
          ),
        ] of Amber::Schema::Error)
      end

      schema_entry.factory.call(data).validate
    end

    # Before filter to validate requests
    macro validate_schema(action = nil, required = true)
      # Kept for source compatibility. A declared schema is now enforced
      # automatically, so it cannot accidentally become documentation-only.
    end

    # Macro for auto validation (simplified)
    macro auto_validate
      # Kept for source compatibility. Registered schemas are always enforced.
    end

    # Called from the controller callback pipeline before user callbacks.
    def run_schema_validation(action : Symbol) : Nil
      @schema_action = action.to_s
      return unless Amber::Schema::Registry.request_schema(self.class.name, @schema_action.not_nil!)

      result = validate_request(@schema_action.not_nil!)
      @validation_result = result

      if result.success?
        @request_data = result.data
        return
      end

      error = result.errors.first?
      response.status_code = error.is_a?(Amber::Schema::RequestParseError) ? error.http_status : 422
      response.content_type = "application/json"
      response.print Amber::Schema::ResponseFormatters::JSONResponse.new.unprocessable_entity(result.errors)
      context.content = ""
    end

    # Helper to access validated data (alias for request_data)
    def validated_params : Hash(String, JSON::Any)?
      @request_data
    end

    # Recover the concrete schema type and its generated typed getters.
    def validated_as(type : T.class) : T forall T
      schema = @validated_schema
      raise Amber::Schema::InvalidSchemaError.new("No validated request schema is available") unless schema
      unless schema.is_a?(T)
        raise Amber::Schema::InvalidSchemaError.new("Expected #{T}, got #{schema.class}")
      end
      schema.as(T)
    end

    # Helper to check if validation passed
    def validation_failed? : Bool
      @validation_result && @validation_result.failure?
    end

    # Helper method to respond with schema-validated data
    def respond_with(
      data : Hash(String, JSON::Any) | NamedTuple | Nil = nil,
      status : Int32 = 200,
      schema_name : String? = nil,
      format : Symbol = :auto,
      key_provider : Amber::Schema::COSE::KeyProvider? = Amber::Schema::COSE.key_provider,
    )
      # Convert NamedTuple to Hash if needed
      response_data = case data
                      when NamedTuple
                        data.to_h.transform_values { |v| JSON::Any.new(v) }
                      when Hash
                        data
                      when Nil
                        {} of String => JSON::Any
                      else
                        raise "respond_with only accepts Hash(String, JSON::Any), NamedTuple, or Nil"
                      end

      validation = validate_response(response_data, status, schema_name)
      if validation.failure?
        response.status_code = 500
        response.content_type = "application/json"
        response.print Amber::Schema::ResponseFormatters::JSONResponse.new.error_response(
          500,
          "Response did not satisfy its declared schema",
          "response_schema_mismatch"
        )
        context.content = ""
        return
      end

      response_data = validation.data || response_data

      selected_format = negotiate_schema_format(format)
      if schema_entry = Amber::Schema::Registry.response_schema(
           self.class.name,
           (schema_name || @schema_action || action_name).to_s
         )
        selected_content_type = schema_content_type(selected_format)
        declared = schema_entry.schema_class.content_types
        allowed = declared.empty? ? ["application/json"] : declared
        unless allowed.includes?(selected_content_type)
          response.status_code = 406
          response.content_type = "application/json"
          response.print Amber::Schema::ResponseFormatters::JSONResponse.new.error_response(
            406,
            "The declared response schema does not provide #{selected_content_type}",
            "response_media_type_not_acceptable"
          )
          context.content = ""
          return
        end
      end

      response.status_code = status
      case selected_format
      when :cbor
        response.content_type = "application/cbor"
        response.write Amber::Schema::CBOR.encode(response_data)
      when :cose
        unless provider = key_provider
          response.status_code = 500
          response.content_type = "application/json"
          response.print Amber::Schema::ResponseFormatters::JSONResponse.new.error_response(
            500,
            "COSE response handling is not configured",
            "cose_not_configured"
          )
          context.content = ""
          return
        end
        response.content_type = "application/cose"
        response.headers["X-Amber-Wire-Format"] = "cose-encrypt0;alg=chacha20-poly1305;cbor=deterministic"
        response.write Amber::Schema::COSE.encrypt0(Amber::Schema::CBOR.encode(response_data), provider)
      else
        response.content_type = "application/json"
        response.print response_data.to_json
      end
      response.close
    end

    # Render with response validation (backward compatible)
    def render_validated(data : Hash(String, JSON::Any), status : Int32 = 200)
      respond_with(data, status)
    end

    # Helper to create error response
    def respond_with_error(message : String, status : Int32 = 400, code : String? = nil)
      response_formatter = Amber::Schema::ResponseFormatters::JSONResponse.new
      response.status_code = status
      response.content_type = "application/json"
      response.print response_formatter.error_response(status, message, code)
      response.close
    end

    # Helper to respond with validation errors
    def respond_with_errors(errors : Array(Amber::Schema::Error), status : Int32 = 422)
      response_formatter = Amber::Schema::ResponseFormatters::JSONResponse.new
      response.status_code = status
      response.content_type = "application/json"
      response.print response_formatter.unprocessable_entity(errors)
      response.close
    end

    # Merge request data from all sources (body, query params, path params)
    private def merge_request_data(schema_class : Amber::Schema::Definition.class | Nil = nil) : Hash(String, JSON::Any)
      body_data = parse_request_body(schema_class)
      return merge_unscoped_request_data(body_data) unless schema_class

      route_data = {} of String => JSON::Any
      begin
        if request.valid_route?
          request.route.params.each { |key, value| route_data[key] = JSON::Any.new(value) }
        end
      rescue
        # Unit-created request contexts may not have a resolved route.
      end

      query_data = {} of String => JSON::Any
      request.query_params.each { |key, value| query_data[key] = JSON::Any.new(value) }

      data = {} of String => JSON::Any
      consumed_body_fields = Set(String).new
      schema_class.fields.each do |name, field|
        source_name = field.options["source_name"]?.try(&.as_s?) || name
        value = case field.source
                when Amber::Schema::ParamSource::Path
                  route_data[source_name]?
                when Amber::Schema::ParamSource::Query
                  query_data[source_name]?
                when Amber::Schema::ParamSource::Header
                  request.headers[source_name]?.try { |header| JSON::Any.new(header) }
                when Amber::Schema::ParamSource::Cookie
                  request.cookies[source_name]?.try { |cookie| JSON::Any.new(cookie.value) }
                else
                  consumed_body_fields << source_name
                  body_data[source_name]?
                end
        data[name] = value if value
      end
      body_data.each do |name, value|
        data[name] = value unless consumed_body_fields.includes?(name)
      end
      data
    end

    private def merge_unscoped_request_data(body_data : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
      data = {} of String => JSON::Any
      begin
        if request.valid_route?
          request.route.params.each { |key, value| data[key] = JSON::Any.new(value) }
        end
      rescue
      end
      request.query_params.each { |key, value| data[key] = JSON::Any.new(value) }
      data.merge!(body_data)
      data
    end

    # Parse request body based on content type
    private def parse_request_body(schema_class : Amber::Schema::Definition.class | Nil = nil) : Hash(String, JSON::Any)
      Amber::Schema::Parser::ParserRegistry.parse_request(request, schema_class)
    end

    private def negotiate_schema_format(requested : Symbol) : Symbol
      return requested unless requested == :auto
      accept = request.headers["Accept"]? || ""
      return :cose if accept.includes?("application/cose")
      return :cbor if accept.includes?("application/cbor")
      :json
    end

    private def schema_content_type(format : Symbol) : String
      case format
      when :cbor then "application/cbor"
      when :cose then "application/cose"
      else            "application/json"
      end
    end

    private def enforce_schema_content_type!(schema_class : Amber::Schema::Definition.class) : Nil
      return unless request.body
      declared = schema_class.content_types
      allowed = declared.empty? ? ["application/json"] : declared
      actual = (request.headers["Content-Type"]? || "").split(';', 2).first.downcase.strip
      raise Amber::Schema::UnsupportedMediaTypeError.new(actual.empty? ? "missing" : actual) unless allowed.includes?(actual)
    end

    # Get current action name from the context
    private def action_name : String
      # Extract action name from route
      # This assumes route follows pattern "ControllerName#action"
      if route_resource = context.route.resource
        parts = route_resource.split("#")
        parts.last? || "unknown"
      else
        "unknown"
      end
    end
  end
end

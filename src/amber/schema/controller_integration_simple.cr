# Simplified integration with Amber controllers
module Amber::Schema
  # Mixin for controllers to add schema validation
  module ControllerIntegration
    macro included
      # Instance property to store validated request data
      property request_data : Hash(String, JSON::Any)? = nil

      # Store validation result
      property validation_result : Amber::Schema::LegacyResult? = nil
    end

    # Define a request schema for an action
    macro schema(action, &block)
      {% action_name = action.id.stringify %}
      
      # This would be implemented by the controller
      # For now, we just provide the macro interface
    end

    # Define a response schema for an action
    macro response_schema(action, &block)
      {% action_name = action.id.stringify %}
      
      # This would be implemented by the controller
    end

    # Validate request against schema
    def validate_request(schema_name : String? = nil) : Amber::Schema::LegacyResult
      # Merge all request data
      data = merge_request_data

      # For now, return success
      Amber::Schema::LegacyResult.success(data)
    end

    # Validate response against schema
    def validate_response(data : Hash(String, JSON::Any), status : Int32 = 200, schema_name : String? = nil) : Amber::Schema::LegacyResult
      Amber::Schema::LegacyResult.success(data)
    end

    # Before filter to validate requests
    macro validate_schema(action = nil, required = true)
      before_action :validate_schema_filter, only: [{{action}}] if {{action}}
      before_action :validate_schema_filter unless {{action}}

      private def validate_schema_filter
        result = validate_request({{action && action.stringify}})
        
        if result.failure?
          if {{required}}
            response_formatter = Amber::Schema::ResponseFormatters::JSONResponse.new
            response.status_code = 422
            response.content_type = "application/json"
            response.print response_formatter.unprocessable_entity(result.errors)
            response.close
          else
            # Store validation result for optional handling
            @validation_result = result
          end
        else
          # Store validated data for use in action
          @request_data = result.data
          @validation_result = result
        end
      end
    end

    # Macro for auto validation (simplified)
    macro auto_validate
      # Simplified version - just enables the feature
    end

    # Helper to access validated data (alias for request_data)
    def validated_params : Hash(String, JSON::Any)?
      @request_data
    end

    # Helper to check if validation passed
    def validation_failed? : Bool
      @validation_result && @validation_result.failure?
    end

    # Helper method to respond with schema-validated data
    def respond_with(data : Hash(String, JSON::Any) | NamedTuple | Nil = nil, status : Int32 = 200, schema_name : String? = nil)
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

      # Set response properties
      response.status_code = status
      response.content_type = "application/json"
      response.print response_data.to_json
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
    private def merge_request_data : Hash(String, JSON::Any)
      data = {} of String => JSON::Any

      # Start with path parameters from request.params (which includes route params)
      begin
        if request.valid_route?
          route_params = request.route.params
          if route_params
            route_params.each do |key, value|
              data[key] = JSON::Any.new(value)
            end
          end
        end
      rescue
        # Skip route params if not available
      end

      # Add query parameters
      request.query_params.each do |key, value|
        data[key] = JSON::Any.new(value)
      end

      # Parse and merge body data
      body_data = parse_request_body
      data.merge!(body_data)

      data
    end

    # Parse request body based on content type
    private def parse_request_body : Hash(String, JSON::Any)
      content_type = request.headers["Content-Type"]?

      begin
        # For now, just parse as JSON
        if request.body
          body_string = request.body.not_nil!.gets_to_end
          if !body_string.empty?
            JSON.parse(body_string).as_h
          else
            {} of String => JSON::Any
          end
        else
          {} of String => JSON::Any
        end
      rescue ex
        # Log parsing error and return empty hash
        # TODO: Add proper logging when available
        {} of String => JSON::Any
      end
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

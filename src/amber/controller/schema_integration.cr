# Integrates Schema API with Amber controllers
require "../schema"

module Amber::Controller
  # Extension module that patches Base controller to include Schema API
  module SchemaIntegration
    macro included
      # Include the Schema::ControllerIntegration module
      include Amber::Schema::ControllerIntegration
      
      # Override the params getter to maintain backward compatibility
      # The original params returns Amber::Validators::Params
      # We'll keep it but also provide access to validated schema data
      protected getter original_params : Amber::Validators::Params
      
      # Create an alias for the original params
      {% unless @type.has_method?(:legacy_params) %}
        protected def legacy_params
          @original_params ||= Amber::Validators::Params.new(context.params)
        end
      {% end %}
      
      # Override params to provide a migration path
      protected def params
        # If we have validated schema data, create a wrapper that provides
        # backward compatibility with the old params interface
        if @request_data
          SchemaParamsWrapper.new(@request_data.not_nil!, context.params)
        else
          # Fall back to original params behavior
          @original_params ||= Amber::Validators::Params.new(context.params)
        end
      end
      
      # Helper method to access raw params when needed
      protected def raw_params
        context.params
      end
    end
  end

  # Wrapper class that provides backward compatibility between Schema API
  # and the existing Amber::Validators::Params interface
  class SchemaParamsWrapper
    getter validated_data : Hash(String, JSON::Any)
    getter raw_params : Amber::Router::Params

    def initialize(@validated_data : Hash(String, JSON::Any), @raw_params : Amber::Router::Params)
    end

    # Delegate array-like access to validated data first, then raw params
    def [](key : String | Symbol)
      key_str = key.to_s
      if validated_data.has_key?(key_str)
        # Convert JSON::Any to string for backward compatibility
        json_value = validated_data[key_str]
        case json_value.raw
        when String
          json_value.as_s
        when Int64
          json_value.as_i.to_s
        when Float64
          json_value.as_f.to_s
        when Bool
          json_value.as_bool.to_s
        when Nil
          ""
        else
          json_value.to_s
        end
      else
        raw_params[key_str]
      end
    end

    def []?(key : String | Symbol)
      key_str = key.to_s
      if validated_data.has_key?(key_str)
        self[key_str]
      else
        raw_params[key_str]?
      end
    end

    # Check if key exists in either validated data or raw params
    def has_key?(key : String | Symbol) : Bool
      key_str = key.to_s
      validated_data.has_key?(key_str) || raw_params.has_key?(key_str)
    end

    # Provide access to validation methods for migration
    def validation(&)
      # Create a temporary Amber::Validators::Params for validation
      validator = Amber::Validators::Params.new(raw_params)
      with Amber::Validators::ValidationBuilder.new(validator) yield
      validator
    end

    # Convert to hash combining validated and raw data
    def to_h
      result = {} of String => String?

      # Start with raw params
      raw_params.to_h.each do |k, v|
        result[k] = v
      end

      # Override with validated data
      validated_data.each do |k, v|
        result[k] = case v.raw
                    when String
                      v.as_s
                    when Int64
                      v.as_i.to_s
                    when Float64
                      v.as_f.to_s
                    when Bool
                      v.as_bool.to_s
                    when Nil
                      nil
                    else
                      v.to_s
                    end
      end

      result
    end

    # Access to raw unvalidated params
    def to_unsafe_h
      raw_params.to_h
    end

    # Forward missing methods to raw params for full compatibility
    forward_missing_to @raw_params
  end
end

# Patch the Base controller to include Schema integration
class Amber::Controller::Base
  include Amber::Controller::SchemaIntegration
end

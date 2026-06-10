# Base schema definition class
# Provides the foundation for defining request/response schemas
require "json"

module Amber::Schema
  class Definition
    # Internal field definition
    struct FieldDef
      property name : String
      property type : String
      property required : Bool = false
      property default : JSON::Any?
      property source : ParamSource = ParamSource::Body
      property validators : Array(Validator::Base) = [] of Validator::Base
      property options : Hash(String, JSON::Any) = {} of String => JSON::Any

      def initialize(@name : String, @type : String, @required : Bool = false, @default : JSON::Any? = nil, @source : ParamSource = ParamSource::Body)
      end
    end

    # Conditional field group
    struct ConditionalGroup
      property condition_field : String
      property condition_value : JSON::Any
      property fields : Array(FieldDef) = [] of FieldDef
      property required_fields : Array(String) = [] of String

      def initialize(@condition_field : String, @condition_value : JSON::Any)
      end
    end

    # Parameter source configuration
    struct SourceBlock
      property source : ParamSource
      property fields : Array(FieldDef) = [] of FieldDef

      def initialize(@source : ParamSource)
      end
    end

    # Class-level storage for schema metadata
    # These need to be initialized per subclass
    macro inherited
      @@fields = {} of String => ::Amber::Schema::Definition::FieldDef
      @@required_fields = [] of String
      @@validators = [] of ::Amber::Schema::Validator::Base
      @@conditional_groups = [] of ::Amber::Schema::Definition::ConditionalGroup
      @@source_blocks = [] of ::Amber::Schema::Definition::SourceBlock
      @@success_type : String? = nil
      @@failure_type : String? = nil
      @@content_types = [] of String

      def self.fields
        @@fields
      end

      def self.required_fields
        @@required_fields
      end

      def self.validators
        @@validators
      end

      def self.conditional_groups
        @@conditional_groups
      end

      def self.source_blocks
        @@source_blocks
      end

      def self.success_type
        @@success_type
      end

      def self.failure_type
        @@failure_type
      end

      def self.content_types
        @@content_types
      end
    end

    # Instance variables
    getter raw_data : Hash(String, JSON::Any)
    getter errors = [] of Error
    # Storage for validated nested schema instances
    @nested_schemas = {} of String => Definition

    def initialize(@raw_data : Hash(String, JSON::Any))
    end

    # Main validation method - returns legacy Result for backward compatibility
    def validate : LegacyResult
      # Clear any previous errors
      @errors.clear

      # Validate required fields
      validate_required_fields

      # Validate field types and constraints
      validate_fields

      # Run custom validators
      run_validators

      # Check conditional requirements
      validate_conditionals

      # Return result based on errors
      if @errors.empty?
        LegacyResult.success(@raw_data)
      else
        LegacyResult.failure(@errors, @raw_data)
      end
    end

    # New validation method that returns typed Result
    def validate_typed : Success(Hash(String, JSON::Any)) | Failure(Hash(String, JSON::Any))
      result = self.validate

      if result.success? && result.data
        Success(Hash(String, JSON::Any)).new(result.data.not_nil!)
      else
        Failure(Hash(String, JSON::Any)).new(ValidationFailure.new(result.errors, @raw_data, result.warnings))
      end
    end

    # DSL Macros

    # Define a field in the schema
    macro field(name, type, **options)
      {% field_name = name.id.stringify %}
      {% type_name = type.stringify %}
      {% required = options[:required] || false %}
      {% default = options[:default] %}
      {% source = options[:source] || "::Amber::Schema::ParamSource::Body" %}
      
      # Field will be stored in class variable
      
      # Add to class storage
      @@fields[{{field_name}}] = FieldDef.new(
        {{field_name}},
        {{type_name}},
        {{required}},
        {% if options.has_key?(:default) %}JSON::Any.new({{default}}){% else %}nil{% end %},
        {{source.id}}
      )
      
      {% if required %}
        @@required_fields << {{field_name}}
      {% end %}
      
      # Store options in field definition
      {% for key, value in options %}
        {% unless key == :required || key == :default || key == :source %}
          {% if value.is_a?(HashLiteral) %}
            # Convert hash literals to JSON-compatible format
            hash_value = {} of String => JSON::Any
            {% for k, v in value %}
              hash_value[{{k.stringify}}] = JSON::Any.new({{v}})
            {% end %}
            @@fields[{{field_name}}].options[{{key.stringify}}] = JSON::Any.new(hash_value)
          {% else %}
            @@fields[{{field_name}}].options[{{key.stringify}}] = JSON::Any.new({{value}})
          {% end %}
        {% end %}
      {% end %}
      
      # Create getter for the field
      def {{name.id}} : {{type}}?
        if value = @raw_data[{{field_name}}]?
          # Use type coercion system
          if coerced = ::Amber::Schema::TypeCoercion.coerce(value, {{type_name}})
            {% if type.stringify == "String" %}
              coerced.as_s
            {% elsif type.stringify == "Int32" %}
              coerced.as_i
            {% elsif type.stringify == "Int64" %}
              coerced.as_i64
            {% elsif type.stringify == "Float32" %}
              coerced.as_f32
            {% elsif type.stringify == "Float64" %}
              coerced.as_f
            {% elsif type.stringify == "Bool" %}
              coerced.as_bool
            {% elsif type.stringify.starts_with?("Array(") %}
              # Extract element type from Array(ElementType)
              {% element_type = type.stringify[6..-2] %}
              if array = coerced.as_a?
                array.map do |item|
                  {% if element_type == "String" %}
                    item.as_s? || item.to_s
                  {% elsif element_type == "Int32" %}
                    item.as_i? || item.as_s.to_i32
                  {% elsif element_type == "Int64" %}
                    item.as_i64? || item.as_s.to_i64
                  {% elsif element_type == "Float32" %}
                    item.as_f32? || item.as_s.to_f32
                  {% elsif element_type == "Float64" %}
                    item.as_f? || item.as_s.to_f64
                  {% elsif element_type == "Bool" %}
                    item.as_bool? || (item.as_s? == "true")
                  {% elsif element_type == "Hash(String, JSON::Any)" %}
                    item.as_h
                  {% else %}
                    item.raw
                  {% end %}
                end
              else
                nil
              end
            {% elsif type.stringify.starts_with?("Hash(") %}
              coerced.as_h
            {% elsif type.stringify == "Time" %}
              # Coercion returns ISO8601 string, parse it
              if str = coerced.as_s?
                Time.parse_iso8601(str)
              end
            {% elsif type.stringify == "UUID" %}
              # Coercion returns validated UUID string
              if str = coerced.as_s?
                ::UUID.new(str)
              end
            {% elsif type.stringify == "Hash(String, JSON::Any)" %}
              # Return hash data directly
              coerced.as_h
            {% else %}
              coerced.raw.as({{type}})
            {% end %}
          else
            nil
          end
        elsif default = self.class.fields[{{field_name}}].default
          # Apply coercion to default value too
          if coerced = ::Amber::Schema::TypeCoercion.coerce(default, {{type_name}})
            {% if type.stringify == "String" %}
              coerced.as_s
            {% elsif type.stringify == "Int32" %}
              coerced.as_i
            {% elsif type.stringify == "Int64" %}
              coerced.as_i64
            {% elsif type.stringify == "Float32" %}
              coerced.as_f32
            {% elsif type.stringify == "Float64" %}
              coerced.as_f
            {% elsif type.stringify == "Bool" %}
              coerced.as_bool
            {% elsif type.stringify.starts_with?("Array(") %}
              # Extract element type from Array(ElementType)
              {% element_type = type.stringify[6..-2] %}
              if array = coerced.as_a?
                array.map do |item|
                  {% if element_type == "String" %}
                    item.as_s? || item.to_s
                  {% elsif element_type == "Int32" %}
                    item.as_i? || item.as_s.to_i32
                  {% elsif element_type == "Int64" %}
                    item.as_i64? || item.as_s.to_i64
                  {% elsif element_type == "Float32" %}
                    item.as_f32? || item.as_s.to_f32
                  {% elsif element_type == "Float64" %}
                    item.as_f? || item.as_s.to_f64
                  {% elsif element_type == "Bool" %}
                    item.as_bool? || (item.as_s? == "true")
                  {% elsif element_type == "Hash(String, JSON::Any)" %}
                    item.as_h
                  {% else %}
                    item.raw
                  {% end %}
                end
              else
                nil
              end
            {% elsif type.stringify == "Time" %}
              if str = coerced.as_s?
                Time.parse_iso8601(str)
              end
            {% elsif type.stringify == "UUID" %}
              if str = coerced.as_s?
                ::UUID.new(str)
              end
            {% elsif type.stringify == "Hash(String, JSON::Any)" %}
              # Return hash data directly
              coerced.as_h
            {% else %}
              coerced.raw.as({{type}})
            {% end %}
          else
            nil
          end
        else
          nil
        end
      rescue
        nil
      end
    end

    # Define a nested schema field
    macro nested(name, schema_class)
      {% field_name = name.id.stringify %}
      
      field {{name}}, Hash(String, JSON::Any)
      
      # Create typed getter for nested schema
      def {{name.id}}_schema : {{schema_class}}?
        @nested_schemas[{{field_name}}]?.try(&.as({{schema_class}}))
      end
      
      # Add nested schema validation
      @@validators << ::Amber::Schema::Validator::Custom.new do |context|
        if data = context.data[{{field_name}}]?
          if hash_data = data.as_h?
            nested_schema = {{schema_class}}.new(hash_data)
            nested_result = nested_schema.validate
            
            if nested_result.success?
              # Store the validated nested schema for later access
              context.schema.@nested_schemas[{{field_name}}] = nested_schema
            else
              nested_result.errors.each do |error|
                # Prefix field name with parent field
                prefixed_error = ::Amber::Schema::Error.new(
                  {{field_name}} + "." + error.field,
                  error.message || "Validation failed",
                  error.code,
                  error.details
                )
                context.add_error(prefixed_error)
              end
            end
          end
        end
      end
    end

    # Helper macro for defining multiple fields that must be present together
    macro requires_together(*fields)
      @@validators << ::Amber::Schema::Validator::Custom.new do |context|
        field_names = {{fields.map(&.stringify)}}
        present_fields = field_names.select { |f| context.field_exists?(f) }
        
        if present_fields.size > 0 && present_fields.size < field_names.size
          missing = field_names - present_fields
          context.add_error(::Amber::Schema::CustomValidationError.new(
            missing.first,
            "Fields #{field_names.join(", ")} must be present together",
            "requires_together"
          ))
        end
      end
    end

    # Helper macro for requiring exactly one of a set of fields
    macro requires_one_of(*fields)
      @@validators << ::Amber::Schema::Validator::Custom.new do |context|
        field_names = {{fields.map(&.stringify)}}
        present_fields = field_names.select { |f| context.field_exists?(f) }
        
        if present_fields.size == 0
          context.add_error(::Amber::Schema::CustomValidationError.new(
            field_names.first,
            "One of #{field_names.join(", ")} must be present",
            "requires_one_of"
          ))
        elsif present_fields.size > 1
          context.add_error(::Amber::Schema::CustomValidationError.new(
            present_fields[1],
            "Only one of #{field_names.join(", ")} can be present",
            "requires_one_of"
          ))
        end
      end
    end

    # Define success and failure types
    macro validates_to(success_type, failure_type = ValidationError)
      @@success_type = {{success_type.stringify}}
      @@failure_type = {{failure_type.stringify}}
    end

    # Define supported content types
    macro content_type(*types)
      {% for type in types %}
        @@content_types << {{type}}
      {% end %}
    end

    # Define conditional field requirements
    macro when_field(field, value)
      {% field_name = field.stringify %}
      
      # Store current conditional context
      %current_conditional = ConditionalGroup.new({{field_name}}, JSON::Any.new({{value}}))
      
      # Process the block in conditional context
      macro field(name, type, **options)
        {% field_name = name.id.stringify %}
        {% type_name = type.stringify %}
        {% required = options[:required] || false %}
        
        field_def = FieldDef.new(
          \{{field_name}},
          \{{type_name}},
          \{{required}}
        )
        
        # Add options
        {% for key, value in options %}
          {% unless key == :required || key == :default || key == :source %}
            {% if value.is_a?(HashLiteral) %}
              # Convert hash literals to JSON-compatible format
              hash_value = {} of String => JSON::Any
              {% for k, v in value %}
                hash_value[\{{k.stringify}}] = JSON::Any.new(\{{v}})
              {% end %}
              field_def.options[\{{key.stringify}}] = JSON::Any.new(hash_value)
            {% else %}
              field_def.options[\{{key.stringify}}] = JSON::Any.new(\{{value}})
            {% end %}
          {% end %}
        {% end %}
        
        %current_conditional.fields << field_def
        
        {% if required %}
          %current_conditional.required_fields << \{{field_name}}
        {% end %}
      end
      
      # Process nested block
      {{yield}}
      
      # Add conditional group to schema
      @@conditional_groups << %current_conditional
    end

    # Define fields that must be present together
    macro when_present(field)
      {% field_name = field.stringify %}
      
      # Store current conditional context
      %current_conditional = ConditionalGroup.new({{field_name}}, JSON::Any.new("__present__"))
      
      # Process the block in conditional context - reuse when_field macro logic
      macro field(name, type, **options)
        {% field_name = name.id.stringify %}
        {% type_name = type.stringify %}
        {% required = options[:required] || false %}
        
        field_def = FieldDef.new(
          \{{field_name}},
          \{{type_name}},
          \{{required}}
        )
        
        # Add options
        {% for key, value in options %}
          {% unless key == :required || key == :default || key == :source %}
            {% if value.is_a?(HashLiteral) %}
              # Convert hash literals to JSON-compatible format
              hash_value = {} of String => JSON::Any
              {% for k, v in value %}
                hash_value[\{{k.stringify}}] = JSON::Any.new(\{{v}})
              {% end %}
              field_def.options[\{{key.stringify}}] = JSON::Any.new(hash_value)
            {% else %}
              field_def.options[\{{key.stringify}}] = JSON::Any.new(\{{value}})
            {% end %}
          {% end %}
        {% end %}
        
        %current_conditional.fields << field_def
        
        {% if required %}
          %current_conditional.required_fields << \{{field_name}}
        {% end %}
      end
      
      # Process nested block
      {{yield}}
      
      # Add conditional group to schema
      @@conditional_groups << %current_conditional
    end

    # Parameter source blocks
    macro from_query
      %current_source = SourceBlock.new(ParamSource::Query)
      
      macro field(name, type, **options)
        # Add field with query source
        field \{{name}}, \{{type}}, source: ParamSource::Query, \{{**options}}
        
        # Also track in source block
        field_def = FieldDef.new(
          \{{name.stringify}},
          \{{type.stringify}},
          \{{options[:required] || false}},
          source: ParamSource::Query
        )
        %current_source.fields << field_def
      end
      
      {{yield}}
      
      @@source_blocks << %current_source
    end

    macro from_path
      %current_source = SourceBlock.new(ParamSource::Path)
      
      macro field(name, type, **options)
        # Add field with path source
        field \{{name}}, \{{type}}, source: ParamSource::Path, \{{**options}}
        
        # Also track in source block
        field_def = FieldDef.new(
          \{{name.stringify}},
          \{{type.stringify}},
          \{{options[:required] || false}},
          source: ParamSource::Path
        )
        %current_source.fields << field_def
      end
      
      {{yield}}
      
      @@source_blocks << %current_source
    end

    macro from_body
      %current_source = SourceBlock.new(ParamSource::Body)
      
      macro field(name, type, **options)
        # Add field with body source
        field \{{name}}, \{{type}}, source: ParamSource::Body, \{{**options}}
        
        # Also track in source block
        field_def = FieldDef.new(
          \{{name.stringify}},
          \{{type.stringify}},
          \{{options[:required] || false}},
          source: ParamSource::Body
        )
        %current_source.fields << field_def
      end
      
      {{yield}}
      
      @@source_blocks << %current_source
    end

    macro from_header
      %current_source = SourceBlock.new(ParamSource::Header)
      
      macro field(name, type, **options)
        # Add field with header source
        field \{{name}}, \{{type}}, source: ParamSource::Header, \{{**options}}
        
        # Also track in source block
        field_def = FieldDef.new(
          \{{name.stringify}},
          \{{type.stringify}},
          \{{options[:required] || false}},
          source: ParamSource::Header
        )
        %current_source.fields << field_def
      end
      
      {{yield}}
      
      @@source_blocks << %current_source
    end

    # Add a custom validator
    macro validate(method_name = nil, &block)
      {% if method_name %}
        # For method-based validators, create a wrapper that calls the method
        # The method is expected to add errors to @errors directly
        @@validators << ::Amber::Schema::Validator::Custom.new do |context|
          # The context.schema is the actual instance being validated
          # We need to call the method on it, but since it adds to @errors
          # and those get transferred later, it should work
          
          # Save the error count before calling the method
          error_count_before = context.schema.errors.size
          
          # Use a case statement to handle different schema types
          case context.schema
          when self
            context.schema.as(self).{{method_name.id}}
          else
            # This shouldn't happen but handle gracefully
          end
          
          # Check if new errors were added
          error_count_after = context.schema.errors.size
          
          # The errors are already in @errors, they'll be handled by run_validators
        end
      {% else %}
        @@validators << Validator::Custom.new({{block}})
      {% end %}
    end

    # Helper methods for validation

    private def validate_required_fields
      self.class.required_fields.each do |field_name|
        unless @raw_data.has_key?(field_name)
          @errors << ::Amber::Schema::RequiredFieldError.new(field_name)
        end
      end
    end

    private def validate_fields
      self.class.fields.each do |field_name, field_def|
        if value = @raw_data[field_name]?
          validate_field_type(field_name, field_def, value)
          validate_field_constraints(field_name, field_def, value)
        end
      end
    end

    private def validate_field_type(field_name : String, field_def : FieldDef, value : JSON::Any)
      # Allow nil values for optional fields
      return if value.raw.nil? && !field_def.required

      # Use type coercion system for validation
      unless ::Amber::Schema::TypeCoercion.can_coerce?(value, field_def.type)
        error_info = ::Amber::Schema::TypeCoercion.coercion_error(field_name, value, field_def.type)
        @errors << ::Amber::Schema::TypeMismatchError.new(field_name, field_def.type, error_info.source_type)
      end
    end

    private def validate_field_constraints(field_name : String, field_def : FieldDef, value : JSON::Any)
      # Skip constraint validation for nil values
      return if value.raw.nil?

      # Validate based on options like min, max, format, etc.
      options = field_def.options

      # For numeric constraints, try to coerce to appropriate numeric type first
      if min = options["min"]?
        numeric_value = nil

        # Try to get numeric value, including coercion from string
        if field_def.type.includes?("Int")
          if coerced = ::Amber::Schema::TypeCoercion.coerce(value, "Int64")
            numeric_value = coerced.as_i64.to_f64
          end
        elsif field_def.type.includes?("Float")
          if coerced = ::Amber::Schema::TypeCoercion.coerce(value, "Float64")
            numeric_value = coerced.as_f
          end
        elsif value.as_i?
          numeric_value = value.as_i.to_f64
        elsif value.as_f?
          numeric_value = value.as_f
        end

        if numeric_value
          if numeric_value < min.as_f
            @errors << ::Amber::Schema::RangeError.new(field_name, min: min.as_f, value: numeric_value)
          end
        end
      end

      if max = options["max"]?
        numeric_value = nil

        # Try to get numeric value, including coercion from string
        if field_def.type.includes?("Int")
          if coerced = ::Amber::Schema::TypeCoercion.coerce(value, "Int64")
            numeric_value = coerced.as_i64.to_f64
          end
        elsif field_def.type.includes?("Float")
          if coerced = ::Amber::Schema::TypeCoercion.coerce(value, "Float64")
            numeric_value = coerced.as_f
          end
        elsif value.as_i?
          numeric_value = value.as_i.to_f64
        elsif value.as_f?
          numeric_value = value.as_f
        end

        if numeric_value
          if numeric_value > max.as_f
            @errors << ::Amber::Schema::RangeError.new(field_name, max: max.as_f, value: numeric_value)
          end
        end
      end

      # For string constraints, coerce to string first if needed
      if min_length = options["min_length"]?
        string_value = if value.as_s?
                         value.as_s
                       elsif coerced = ::Amber::Schema::TypeCoercion.coerce(value, "String")
                         coerced.as_s
                       end

        if string_value
          if string_value.size < min_length.as_i
            @errors << ::Amber::Schema::LengthError.new(field_name, min: min_length.as_i, actual: string_value.size)
          end
        end
      end

      if max_length = options["max_length"]?
        string_value = if value.as_s?
                         value.as_s
                       elsif coerced = ::Amber::Schema::TypeCoercion.coerce(value, "String")
                         coerced.as_s
                       end

        if string_value
          if string_value.size > max_length.as_i
            @errors << ::Amber::Schema::LengthError.new(field_name, max: max_length.as_i, actual: string_value.size)
          end
        end
      end

      # Enum validation
      if enum_values = options["enum"]?
        if enum_array = enum_values.as_a?
          value_str = value.to_s
          unless enum_array.any? { |v| v.to_s == value_str }
            @errors << ::Amber::Schema::CustomValidationError.new(
              field_name,
              "Value must be one of: #{enum_array.map(&.to_s).join(", ")}",
              "invalid_enum_value"
            )
          end
        end
      end

      # Format validation
      if format = options["format"]?
        validate_format(field_name, value, format.as_s)
      end

      # Pattern validation (regex)
      if pattern = options["pattern"]?
        if string_value = value.as_s?
          regex = Regex.new(pattern.as_s)
          unless string_value.matches?(regex)
            @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "pattern #{pattern}", string_value)
          end
        end
      end

      # File validation (for File type fields)
      if field_def.type == "Hash(String, JSON::Any)" &&
         (options.has_key?("max_size") || options.has_key?("allowed_types") ||
         options.has_key?("allowed_extensions") || options.has_key?("filename_pattern"))
        file_errors = Parser::FileUploadValidator.validate_file(field_name, value, options)
        file_errors.each { |error| @errors << error }
      end
    end

    private def validate_format(field_name : String, value : JSON::Any, format : String)
      string_value = value.as_s? || return

      case format
      when "email"
        unless string_value.matches?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
          @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "email", string_value)
        end
      when "url", "uri"
        begin
          uri = URI.parse(string_value)
          # A valid URL should have at least a scheme and host
          unless uri.scheme && uri.host && !uri.host.not_nil!.empty?
            @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "URL", string_value)
          end
        rescue
          @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "URL", string_value)
        end
      when "uuid"
        begin
          UUID.new(string_value)
        rescue
          @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "UUID", string_value)
        end
      when "iso8601", "datetime"
        begin
          Time.parse_iso8601(string_value)
        rescue
          @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "ISO8601 datetime", string_value)
        end
      when "date"
        unless string_value.matches?(/\A\d{4}-\d{2}-\d{2}\z/)
          @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "date (YYYY-MM-DD)", string_value)
        end
      when "time"
        unless string_value.matches?(/\A\d{2}:\d{2}(:\d{2})?\z/)
          @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "time (HH:MM[:SS])", string_value)
        end
      when "ipv4"
        unless string_value.matches?(/\A((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/)
          @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "IPv4 address", string_value)
        end
      when "ipv6"
        unless string_value.matches?(/\A(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))\z/)
          @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "IPv6 address", string_value)
        end
      when "hostname"
        unless string_value.matches?(/\A[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\z/)
          @errors << ::Amber::Schema::InvalidFormatError.new(field_name, "hostname", string_value)
        end
      else
        # Custom format - treat as regex pattern
        begin
          regex = Regex.new(format)
          unless string_value.matches?(regex)
            @errors << ::Amber::Schema::InvalidFormatError.new(field_name, format, string_value)
          end
        rescue
          # Invalid regex format
          @errors << ::Amber::Schema::CustomValidationError.new(field_name, "Invalid format specification: #{format}", "invalid_format")
        end
      end
    end

    private def run_validators
      # Create a temporary result to collect errors from validators
      temp_result = LegacyResult.success(@raw_data)
      context = Validator::Context.new(@raw_data, temp_result, self)

      self.class.validators.each do |validator|
        validator.validate(context)
      end

      # Add any errors from context to our errors
      context.result.errors.each do |error|
        @errors << error
      end
    end

    private def validate_conditionals
      self.class.conditional_groups.each do |group|
        # Check if condition is met
        if should_apply_conditional?(group)
          # Validate required fields in this group
          group.required_fields.each do |field_name|
            unless @raw_data.has_key?(field_name)
              @errors << ::Amber::Schema::RequiredFieldError.new(field_name)
            end
          end

          # Validate fields defined in this group
          group.fields.each do |field_def|
            if value = @raw_data[field_def.name]?
              validate_field_type(field_def.name, field_def, value)
              validate_field_constraints(field_def.name, field_def, value)
            elsif field_def.required
              @errors << RequiredFieldError.new(field_def.name)
            end
          end
        end
      end
    end

    private def should_apply_conditional?(group : ConditionalGroup) : Bool
      if group.condition_value.as_s? == "__present__"
        # Special case for when_present
        @raw_data.has_key?(group.condition_field)
      else
        # Check if field value matches condition
        if value = @raw_data[group.condition_field]?
          value == group.condition_value
        else
          false
        end
      end
    end

    # Class methods for introspection
    def self.has_field?(name : String) : Bool
      @@fields.has_key?(name)
    end

    def self.field_names : Array(String)
      @@fields.keys
    end

    def self.required_field_names : Array(String)
      @@required_fields
    end

    def self.uses_path_params? : Bool
      @@source_blocks.any? { |block| block.source == ParamSource::Path }
    end

    def self.uses_query_params? : Bool
      @@source_blocks.any? { |block| block.source == ParamSource::Query }
    end

    def self.uses_body_params? : Bool
      @@source_blocks.any? { |block| block.source == ParamSource::Body }
    end

    def self.uses_header_params? : Bool
      @@source_blocks.any? { |block| block.source == ParamSource::Header }
    end

    # Parse incoming data and return a result
    def parse : LegacyResult
      validate
    end

    # Convert validated data to hash
    def to_h : Hash(String, JSON::Any)
      @raw_data
    end

    # Check if schema has conditionals
    def self.has_conditionals? : Bool
      !@@conditional_groups.empty?
    end

    # Get all conditionals for introspection
    def self.conditionals : Array(ConditionalGroup)
      @@conditional_groups
    end
  end

  # Parameter source enumeration
  enum ParamSource
    Path
    Query
    Body
    Header
    Cookie
    Form
    Multipart
  end
end

# DSL for defining schemas in a more intuitive way
module Amber::Schema
  module DSL
    # Field definition DSL methods
    macro string(name, required = false, **options)
      field({{name.stringify}}, String, {{required}}, {{**options}})
    end

    macro integer(name, required = false, **options)
      field({{name.stringify}}, Int32, {{required}}, {{**options}})
    end

    macro float(name, required = false, **options)
      field({{name.stringify}}, Float64, {{required}}, {{**options}})
    end

    macro boolean(name, required = false, **options)
      field({{name.stringify}}, Bool, {{required}}, {{**options}})
    end

    macro array(name, of type = JSON::Any, required = false, **options)
      field({{name.stringify}}, Array({{type}}), {{required}}, {{**options}})
    end

    macro hash(name, required = false, **options)
      field({{name.stringify}}, Hash(String, JSON::Any), {{required}}, {{**options}})
    end

    macro datetime(name, required = false, **options)
      field({{name.stringify}}, Time, {{required}}, {{**options}})
    end

    # Validation DSL methods
    macro validates_length(field, min = nil, max = nil)
      @fields[{{field.stringify}}].validators << Validator::Length.new(
        {{field.stringify}},
        {{min}},
        {{max}}
      )
    end

    macro validates_range(field, min = nil, max = nil)
      @fields[{{field.stringify}}].validators << Validator::Range.new(
        {{field.stringify}},
        {{min}},
        {{max}}
      )
    end

    macro validates_format(field, format)
      @fields[{{field.stringify}}].validators << Validator::Format.new(
        {{field.stringify}},
        Validator::Format::FormatType::{{format.id.capitalize}}
      )
    end

    macro validates_pattern(field, pattern, message = nil)
      @fields[{{field.stringify}}].validators << Validator::Pattern.new(
        {{field.stringify}},
        {{pattern}},
        {{message}}
      )
    end

    macro validates_enum(field, values)
      @fields[{{field.stringify}}].validators << Validator::Enum.new(
        {{field.stringify}},
        {{values}}
      )
    end

    # Custom validation
    macro validates(field = nil, &block)
      {% if field %}
        @fields[{{field.stringify}}].validate do |value|
          {{yield}}
        end
      {% else %}
        validate do |context|
          {{yield}}
        end
      {% end %}
    end

    # Nested schema support
    macro embedded(name, schema_class, required = false, **options)
      field({{name.stringify}}, Hash(String, JSON::Any), {{required}}, {{**options}})
      
      # Add custom validator for nested schema
      @validators << Validator::Custom.new do |context|
        if nested_data = context.field_value({{name.stringify}})
          if hash = nested_data.as_h?
            nested_schema = {{schema_class}}.new
            nested_result = nested_schema.validate(hash)
            
            nested_result.errors.each do |error|
              # Prefix field path
              prefixed_field = "#{{{name.stringify}}}.#{error.field}"
              context.add_error(
                Error.new(prefixed_field, error.message, error.code, error.details)
              )
            end
          end
        end
      end
    end

    # Array of embedded schemas
    macro embedded_array(name, schema_class, required = false, **options)
      field({{name.stringify}}, Array(Hash(String, JSON::Any)), {{required}}, {{**options}})
      
      # Add custom validator for array of nested schemas
      @validators << Validator::Custom.new do |context|
        if array_data = context.field_value({{name.stringify}})
          if array = array_data.as_a?
            array.each_with_index do |item, index|
              if hash = item.as_h?
                nested_schema = {{schema_class}}.new
                nested_result = nested_schema.validate(hash)
                
                nested_result.errors.each do |error|
                  # Prefix field path with array index
                  prefixed_field = "#{{{name.stringify}}}[#{index}].#{error.field}"
                  context.add_error(
                    Error.new(prefixed_field, error.message, error.code, error.details)
                  )
                end
              end
            end
          end
        end
      end
    end

    # Conditional validation
    macro validates_if(condition, &block)
      @validators << Validator::Conditional.new(
        ->(context : Validator::Context) { {{condition}} },
        Validator::Custom.new do |context|
          {{yield}}
        end
      )
    end

    # Group related validations
    macro validation_group(name, &block)
      # This is mainly for documentation/organization
      # The validations still execute normally
      {{yield}}
    end
  end

  # DSL will be included in the actual schema classes
end

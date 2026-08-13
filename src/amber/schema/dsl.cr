# Shorthand macros that delegate to Definition's authoritative field contract.
module Amber::Schema
  module DSL
    macro string(name, required = false, **options)
      field {{name}}, String, required: {{required}}{% for key, value in options %}, {{key.id}}: {{value}}{% end %}
    end

    macro integer(name, required = false, **options)
      field {{name}}, Int32, required: {{required}}{% for key, value in options %}, {{key.id}}: {{value}}{% end %}
    end

    macro float(name, required = false, **options)
      field {{name}}, Float64, required: {{required}}{% for key, value in options %}, {{key.id}}: {{value}}{% end %}
    end

    macro boolean(name, required = false, **options)
      field {{name}}, Bool, required: {{required}}{% for key, value in options %}, {{key.id}}: {{value}}{% end %}
    end

    macro array(name, of type = JSON::Any, required = false, **options)
      field {{name}}, Array({{type}}), required: {{required}}{% for key, value in options %}, {{key.id}}: {{value}}{% end %}
    end

    macro hash(name, required = false, **options)
      field {{name}}, Hash(String, JSON::Any), required: {{required}}{% for key, value in options %}, {{key.id}}: {{value}}{% end %}
    end

    macro datetime(name, required = false, **options)
      field {{name}}, Time, required: {{required}}{% for key, value in options %}, {{key.id}}: {{value}}{% end %}
    end

    macro validates_length(field, min = nil, max = nil)
      {% unless min.is_a?(NilLiteral) %}
        @@fields[{{field.id.stringify}}].options["min_length"] = JSON::Any.new({{min}})
      {% end %}
      {% unless max.is_a?(NilLiteral) %}
        @@fields[{{field.id.stringify}}].options["max_length"] = JSON::Any.new({{max}})
      {% end %}
    end

    macro validates_range(field, min = nil, max = nil)
      {% unless min.is_a?(NilLiteral) %}
        @@fields[{{field.id.stringify}}].options["min"] = JSON::Any.new({{min}})
      {% end %}
      {% unless max.is_a?(NilLiteral) %}
        @@fields[{{field.id.stringify}}].options["max"] = JSON::Any.new({{max}})
      {% end %}
    end

    macro validates_format(field, format)
      {% format_value = format.is_a?(SymbolLiteral) ? format.id.stringify : format %}
      @@fields[{{field.id.stringify}}].options["format"] = JSON::Any.new({{format_value}})
    end

    macro validates_pattern(field, pattern, message = nil)
      @@fields[{{field.id.stringify}}].options["pattern"] = JSON::Any.new({{pattern}})
    end

    macro validates_enum(field, values)
      @@fields[{{field.id.stringify}}].options["enum"] = JSON::Any.new([
        {% for value in values %}
          JSON::Any.new({{value}}),
        {% end %}
      ] of JSON::Any)
    end

    macro validates(field = nil, &block)
      {% block_argument = block.args.first? %}
      {% if field %}
        @@validators << Validator::Custom.new do |context|
          if %value = context.field_value({{field.id.stringify}})
            {% if block_argument %}
              {{block_argument.id}} = %value
            {% end %}
            %valid = begin
              {{block.body}}
            end
            if %valid == false
              context.add_error(CustomValidationError.new(
                {{field.id.stringify}},
                "Field '#{{{field.id.stringify}}}' failed custom validation"
              ))
            end
          end
        end
      {% else %}
        @@validators << Validator::Custom.new do |context|
          {% if block_argument %}
            {{block_argument.id}} = context
          {% end %}
          {{block.body}}
        end
      {% end %}
    end

    macro embedded(name, schema_class, required = false, **options)
      nested {{name}}, {{schema_class}}, required: {{required}}{% for key, value in options %}, {{key.id}}: {{value}}{% end %}
    end

    macro embedded_array(name, schema_class, required = false, **options)
      {% field_name = name.id.stringify %}
      field {{name}}, Array(Hash(String, JSON::Any)), required: {{required}}{% for key, value in options %}, {{key.id}}: {{value}}{% end %}
      @@nested_array_schemas[{{field_name}}] = {{schema_class}}

      @@validators << Validator::Custom.new do |context|
        if array_data = context.field_value({{field_name}})
          if array = array_data.as_a?
            array.each_with_index do |item, index|
              if hash = item.as_h?
                result = {{schema_class}}.new(hash).validate
                result.errors.each do |error|
                  context.add_error(Error.new(
                    {{field_name}} + "[#{index}].#{error.field}",
                    error.message || "Validation failed",
                    error.code,
                    error.details
                  ))
                end
              end
            end
          end
        end
      end
    end

    macro validates_if(condition, &block)
      {% block_argument = block.args.first? %}
      @@validators << Validator::Conditional.new(
        ->(context : Validator::Context) { {{condition}} },
        Validator::Custom.new do |context|
          {% if block_argument %}
            {{block_argument.id}} = context
          {% end %}
          {{block.body}}
        end
      )
    end

    macro validation_group(name, &block)
      {{block.body}}
    end
  end
end

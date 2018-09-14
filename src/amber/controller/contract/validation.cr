module Contract
  module Validation
    VERSION = "0.1.0"

    TYPES             = [Nil, String, Bool, Int32, Int64, Float32, Float64, Time, Bytes, Array(Any), Hash(Any, Any)]
    TIME_FORMAT_REGEX = /\d{4,}-\d{2,}-\d{2,}\s\d{2,}:\d{2,}:\d{2,}/
    DATETIME_FORMAT   = "%F %X%z"

    {% begin %}
      alias Any = Union({{*TYPES}})
    {% end %}

    record Error, param : String, value : Any, message : String

    macro param(attribute, **options)
      {% TYPES << attribute.type %}
      {% FIELD_OPTIONS[attribute.var] = options %}
      {% CONTENT_FIELDS[attribute.var] = options || {} of Nil => Nil %}
      {% CONTENT_FIELDS[attribute.var][:type] = attribute.type %}
    end

    macro param!(attribute, **options)
      param {{attribute}}, {{options.double_splat(", ")}}raise_on_nil: true
    end

    macro included
      CONTENT_FIELDS = {} of Nil => Nil
      FIELD_OPTIONS = {} of Nil => Nil

      macro finished
        __process_params
      end
    end

    class ValidationError < Exception
      getter errors : Array(Error)

      def initialize(@errors)
      end
    end

    private macro __process_params
      alias Key = String | Symbol

      getter errors = [] of Error

      {% for name, options in FIELD_OPTIONS %}
        {% type = options[:type] %}
        {% property_name = name.id %}
        {% suffixes = options[:raise_on_nil] ? ["?", ""] : ["", "!"] %}
        {% if options[:json_options] %}
          @[JSON::Field({{**options[:json_options]}})]
        {% end %}
        {% if options[:yaml_options] %}
          @[YAML::Field({{**options[:yaml_options]}})]
        {% end %}

        {% if options[:comment] %}
          {{options[:comment].id}}
        {% end %}
        property{{suffixes[0].id}} {{name.id}} : Union({{type.id}} | Nil)

        def {{name.id}}{{suffixes[1].id}}
          raise {{@type.name.stringify}} + "#" + {{name.stringify}} + " cannot be nil" if @{{name.id}}.nil?
          @{{name.id}}.not_nil!
        end

        def {{property_name}}{{suffixes[1].id}}
          raise {{@type.name.stringify}} + "#" + {{property_name.stringify}} + " cannot be nil" if @{{property_name}}.nil?
          @{{property_name}}.not_nil!
        end
      {% end %}

      {% properties = FIELD_OPTIONS.keys.map { |p| p.id } %}
      def_equals_and_hash {{*properties}}

      def initialize(@raw_params : Amber::Router::Params, key : String)
        {% for name, options in FIELD_OPTIONS %}
          {% field_type = CONTENT_FIELDS[name][:type] %}
          param_key = !key.empty? ? "#{key}.{{name.id}}" : {{name.id.stringify}}
          {% if field_type.is_a?(Generic) %}
            {% sub_type = field_type.type_vars %}
            @{{name.id}} = @raw_params.fetch_all(param_key).map do |item|
              cast(item, typeof({{sub_type.join('|').id}})).as({{sub_type.join('|').id}})
            end
          {% else %}
            @{{name.id}} = cast(@raw_params[param_key], {{field_type}}).as({{field_type}})
          {% end %}
        {% end %}
      end

      def valid?
        errors.clear
        validate
        errors.empty?
      end

      def valid!
        valid? || raise ValidationError.new(errors)
      end

      def error(attribute, value, message)
        @errors << Error.new(attribute, value, message)
      end

      private def cast(value : Any, cast_type : Class)
        case cast_type
        when String.class then value.to_s
        when Bool.class then [1,true, 0, false, nil].includes?(value)
        when Int32.class then value.is_a?(String) ? value.to_i32(strict: false) : value.as(Int32)
        when Int64.class then value.is_a?(String) ? value.to_i64(strict: false) : value.as(Int64)
        when Float32.class then value.is_a?(String) ? value.to_f32(strict: false) : value.as(Float32)
        when Float64.class then value.is_a?(String) ? value.to_f64(strict: false) : value.as(Float64)
        else value
        end
      end

      def to_h
        fields = {} of String => Any

        {% for name, options in FIELD_OPTIONS %}
          {% type = options[:type] %}
          {% if type.id == Time.id %}
            fields["{{name}}"] = {{name.id}}.try(&.to_s(DATETIME_FORMAT))
          {% elsif type.id == Slice.id %}
            fields["{{name}}"] = {{name.id}}.try(&.to_s(""))
          {% else %}
            fields["{{name}}"] = {{name.id}}
          {% end %}
        {% end %}

        fields
      end

      def validate
        {% for name, options in FIELD_OPTIONS %}
          {% property_name = name.id %}
          unless {{property_name}}.nil?
            value = {{property_name}}.not_nil!

            {% if options[:be] %}
              error({{property_name.stringify}}, value, "must be {{options[:be].id}}") unless value === {{options[:be]}}
            {% end %}

            {% if options[:eq] %}
              error({{property_name.stringify}}, value, "must be equal to {{options[:eq].id}}") unless value == {{options[:eq]}}
            {% end %}

            {% if options[:gte] %}
              error({{property_name.stringify}}, value, "must be greater than or equal to {{options[:gte].id}}") unless value >= {{options[:gte]}}
            {% end %}

            {% if options[:lte] %}
              error({{property_name.stringify}}, value, "must be less than or equal to {{options[:lte].id}}") unless value <= {{options[:lte]}}
            {% end %}

            {% if options[:gt] %}
              error({{property_name.stringify}}, value, "must be greater than {{options[:gt].id}}") unless value > {{options[:gt]}}
            {% end %}

            {% if options[:lt] %}
              error({{property_name.stringify}}, value, "must be less than {{options[:lt].id}}") unless value < {{options[:lt]}}
            {% end %}

            {% if options[:in] %}
              error({{property_name.stringify}}, value, "must be in {{options[:in].join(", ").id}}") unless {{options[:in]}}.includes?(value)
            {% end %}

            {% if options[:length] %}
              error({{property_name.stringify}}, value, "must have size in {{options[:length].id}}") unless {{options[:length]}}.includes?(value.size)
            {% end %}

            {% if options[:regex] %}
              error({{property_name.stringify}}, value, "must match " + {{options[:regex].stringify}}) unless ({{options[:regex]}}).match(value)
            {% end %}
          end
        {% end %}
      end
    end
  end
end

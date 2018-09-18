module Contract
  module Validation
    TYPES = [
      Nil, Bool, Int32, Int64, Float64, String, Array(Any), Hash(String, Any),
      Range(Int32, Int32), Regex,
    ]

    TIME_FORMAT_REGEX = /\d{4,}-\d{2,}-\d{2,}\s\d{2,}:\d{2,}:\d{2,}/
    DATETIME_FORMAT   = "%F %X%z"

    {% begin %}
    alias Any = Union({{*TYPES}})
    {% end %}

    class Error
      property attribute : Contract::Key, value : String, message : String

      def initialize(validator : Contract::Validator)
        @attribute = validator.attribute
        @value = validator.value.to_s
        @message = validator.message
      end

      def initialize(@attribute, @value, @message)
      end
    end

    macro param(attribute, **options)
      {% FIELD_OPTIONS[attribute.var] = options %}
      {% CONTENT_attributes[attribute.var] = options || {} of Nil => Nil %}
      {% CONTENT_attributes[attribute.var][:type] = attribute.type %}
    end

    macro param!(attribute, **options)
      param {{attribute}}, {{options.double_splat(", ")}}raise_on_nil: true
    end

    macro included
      CONTENT_attributes = {} of Nil => Nil
      FIELD_OPTIONS = {} of Nil => Nil

      macro finished
        __process_params
      end
    end

    private macro __process_params
      getter rules = [] of Contract::Validator
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
          {% field_type = CONTENT_attributes[name][:type] %}
          param_key = !key.empty? ? "#{key}.{{name.id}}" : {{name.id.stringify}}

          {% if field_type.is_a?(Generic) %}
            {% sub_type = field_type.type_vars %}
            @{{name.id}} = @raw_params.fetch_all(param_key).map do |item|
              Contract::Cast.convert!(item, {{sub_type.join('|').id}}).as({{sub_type.join('|').id}})
            end
          {% else %}
            @{{name.id}} = Contract::Cast.convert!(@raw_params[param_key], {{field_type}}).as({{field_type}})
          {% end %}

          {% for key, expected_value in options %}
            {% if Contract::VALIDATOR.keys.includes?(key) %}
            rules << Contract::VALIDATOR[:{{key.id}}].new({{name.id.stringify}}, @{{name.id}}, {{options[key]}})
            {% end %}
          {% end %}
        {% end %}
      end

      def valid?
        errors.clear
        validate
        errors.empty?
      end

      def valid!
        valid? || raise Contract::Error.new(errors)
      end

      def validate
        @rules.each do |validator|
          @errors << Error.new(validator) unless validator.valid?
        end
      end

      def error(attribute, value, message)
        @errors << Validator::Error.new(attribute, value, message)
      end

      def to_h
        attributes = {} of String => {{TYPES.join('|').id}}

        {% for name, options in FIELD_OPTIONS %}
          {% type = options[:type] %}
          {% if type.id == Time.id %}
            attributes["{{name}}"] = {{name.id}}.try(&.to_s(DATETIME_FORMAT))
          {% elsif type.id == Slice.id %}
            attributes["{{name}}"] = {{name.id}}.try(&.to_s(""))
          {% else %}
            attributes["{{name}}"] = {{name.id}}
          {% end %}
        {% end %}

        attributes
      end
    end
  end
end

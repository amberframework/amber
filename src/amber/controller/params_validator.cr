class Hash(K, V)
  def fetch_or_set(key, value)
    if has_key?(key)
      self.[key]
    else
      self.[key] = value
    end
  end
end

module ParamsValidator
  VERSION           = "0.1.0"
  TYPES             = [Nil, String, Bool, Int32, Int64, Float32, Float64, Time, Bytes]
  TIME_FORMAT_REGEX = /\d{4,}-\d{2,}-\d{2,}\s\d{2,}:\d{2,}:\d{2,}/
  DATETIME_FORMAT   = "%F %X%z"

  {% begin %}
    alias Any = Union({{*TYPES}})
  {% end %}

  record Error, param : String, value : Any, message : String

  class ValidationError < Exception
    getter errors : Array(Error)

    def initialize(@errors)
    end
  end

  macro included
    CONTENT_FIELDS = {} of Nil => Nil
    FIELD_OPTIONS = {} of Nil => Nil

    {% unless @type.has_method?("validate") %}
      # Run validations, clearing `#errors` before.
      def validate
        errors.clear
      end
    {% end %}
    macro finished
      __process_params
    end
  end

  macro param(attribute, **options)
    {% FIELD_OPTIONS[attribute.var] = options %}
    {% CONTENT_FIELDS[attribute.var] = options || {} of Nil => Nil %}
    {% CONTENT_FIELDS[attribute.var][:type] = attribute.type %}
  end

  macro param!(attribute, **options)
    param {{attribute}}, {{options.double_splat(", ")}}raise_on_nil: true
  end

  private macro __process_params
    def initialize(@raw_params : Amber::Router::Params, key : String)
      {% for name, options in FIELD_OPTIONS %}
        if !key.empty?
         cast({{name.id.stringify}}, @raw_params["#{key}.{{name.id}}"].as(Any))
        else
         cast({{name.id.stringify}}, @raw_params[{{name.id.stringify}}].as(Any))
        end
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

    private def cast(name, value : Any)
      {% unless CONTENT_FIELDS.empty? %}
        case name.to_s
          {% for _name, _options in CONTENT_FIELDS %}
            {% type = _options[:type] %}
          when "{{_name.id}}"

            return @{{_name.id}} = nil if value.nil?
            {% if type.id == Int32.id %}
              @{{_name.id}} = value.is_a?(String) ? value.to_i32(strict: false) : value.is_a?(Int64) ? value.to_i32 : value.as(Int32)
            {% elsif type.id == Int64.id %}
              @{{_name.id}} = value.is_a?(String) ? value.to_i64(strict: false) : value.as(Int64)
            {% elsif type.id == Float32.id %}
              @{{_name.id}} = value.is_a?(String) ? value.to_f32(strict: false) : value.is_a?(Float64) ? value.to_f32 : value.as(Float32)
            {% elsif type.id == Float64.id %}
              @{{_name.id}} = value.is_a?(String) ? value.to_f64(strict: false) : value.as(Float64)
            {% elsif type.id == Bool.id %}
              @{{_name.id}} = ["1", "yes", "true", true].includes?(value)
            {% elsif type.id == Time.id %}
              if value.is_a?(Time)
                @{{_name.id}} = value
              elsif value.to_s =~ TIME_FORMAT_REGEX
                @{{_name.id}} = Time.parse_utc(value.to_s, DATETIME_FORMAT)
              end
            {% else %}
              @{{_name.id}} = value.to_s
            {% end %}
          {% end %}
        end
      {% end %}
    end

    def validate
      {% for name, options in FIELD_OPTIONS %}
        {% property_name = name.id %}
        unless {{property_name}}.nil?
          value = {{property_name}}.not_nil!

          {% if options[:is] %}
            error({{property_name.stringify}}, value, "must be equal to {{options[:is]}}") unless value == {{options[:is]}}
          {% end %}

          {% if options[:gte] %}
            error({{property_name.stringify}}, value, "must be greater than or equal to {{options[:gte]}}") unless value >= {{options[:gte]}}
          {% end %}

          {% if options[:lte] %}
            error({{property_name.stringify}}, value, "must be less than or equal to {{options[:lte]}}") unless value <= {{options[:lte]}}
          {% end %}

          {% if options[:gt] %}
            error({{property_name.stringify}}, value, "must be greater than {{options[:gt]}}") unless value > {{options[:gt]}}
          {% end %}

          {% if options[:lt] %}
            error({{property_name.stringify}}, value, "must be less than {{options[:lt]}}") unless value < {{options[:lt]}}
          {% end %}

          {% if options[:in] %}
            error({{property_name.stringify}}, value, "must be in {{options[:in].join(", ").id}}") unless {{options[:in]}}.includes?(value)
          {% end %}

          {% if options[:size] %}
            error({{property_name.stringify}}, value, "must have size in {{options[:size]}}") unless {{options[:size]}}.includes?(value.size)
          {% end %}

          {% if options[:regex] %}
            error({{property_name.stringify}}, value, "must match " + {{options[:regex].stringify}}) unless ({{options[:regex]}}).match(value)
          {% end %}
        end
      {% end %}
    end
  end
end

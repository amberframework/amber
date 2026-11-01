require "yaml"

module Amber::Configuration
  # Describes one field that `YAML::Serializable` reads for a registered
  # section type: its YAML key, what kind of value it holds, and, for a
  # nested section, that section's own fields.
  #
  # The `AMBER_*` override pass uses it to name variables, to reach fields
  # that are nil or missing from the loaded YAML, and to turn each variable
  # into a value of the field's type. The credentials reader uses it to read
  # only the files a section declares. :nodoc:
  struct SectionField
    enum Kind
      # A `String` or `String?` field: the value is kept as text.
      Text
      # A `Bool` field: read like the built-in boolean overrides.
      Flag
      # A `Float` field: read like the built-in float overrides.
      Decimal
      # A nested `YAML::Serializable` section.
      Section
      # Any other field: read as a plain YAML scalar.
      Other
    end

    getter key : String
    getter value_kind : Kind
    getter list_of_fields : Array(SectionField)

    def initialize(@key : String, @value_kind : Kind, @list_of_fields : Array(SectionField) = [] of SectionField)
    end

    # Lists the fields `YAML::Serializable` reads for *type*, honoring
    # `@[YAML::Field(key: ...)]` renames and skipping ignored fields.
    def self.list_for(type : T.class) : Array(SectionField) forall T
      list_of_fields = [] of SectionField
      {% for ivar in T.instance_vars %}
        {% field = ivar.annotation(::YAML::Field) %}
        {% unless field && (field[:ignore] || field[:ignore_deserialize]) %}
          {% key = field && field[:key] ? field[:key].id.stringify : ivar.name.stringify %}
          {% types = ivar.type.union_types.reject { |type| type == ::Nil } %}
          {% if field && field[:converter] %}
            list_of_fields << SectionField.new({{ key }}, Kind::Other)
          {% elsif types.size == 1 && types[0] == ::String %}
            list_of_fields << SectionField.new({{ key }}, Kind::Text)
          {% elsif types.size == 1 && types[0] == ::Bool %}
            list_of_fields << SectionField.new({{ key }}, Kind::Flag)
          {% elsif types.size == 1 && types[0] < ::Float %}
            list_of_fields << SectionField.new({{ key }}, Kind::Decimal)
          {% elsif types.size == 1 && types[0] < ::YAML::Serializable %}
            list_of_fields << SectionField.new({{ key }}, Kind::Section, list_for({{ types[0] }}))
          {% else %}
            list_of_fields << SectionField.new({{ key }}, Kind::Other)
          {% end %}
        {% end %}
      {% end %}
      list_of_fields
    end

    # Writes *instance* as a YAML mapping of the fields `YAML::Serializable`
    # reads for its type, including fields marked `ignore_serialize`, so a
    # section rebuilt from this YAML keeps the values *instance* holds.
    # Nested sections are written the same way, and nil values are left out.
    #
    # A field is written only when Amber knows how without asking the type to
    # serialize: its value is a `String`, `Bool`, integer, float, `Time` or
    # enum, an `Array` or `Hash` of the first four, or a nested
    # `YAML::Serializable` section; or its converter is a type that defines
    # its own `to_yaml`. Any other field is left out, and a section rebuilt
    # from this YAML takes that field's declared default. So registering a type
    # never requires it, or its converters, to be writable as YAML.
    #
    # The writer is typed to *T*, so it never dispatches over every
    # `YAML::Serializable` type in the program.
    def self.yaml_of(instance : T) : String forall T
      nodes_builder = YAML::Nodes::Builder.new
      write_every_field(instance, nodes_builder)
      YAML.build { |builder| nodes_builder.document.to_yaml(builder) }
    end

    # :nodoc:
    def self.write_every_field(instance : T, builder : YAML::Nodes::Builder) : Nil forall T
      builder.mapping do
        {% for ivar in T.instance_vars %}
          {% field = ivar.annotation(::YAML::Field) %}
          {% unless field && (field[:ignore] || field[:ignore_deserialize]) %}
            {% key = field && field[:key] ? field[:key].id.stringify : ivar.name.stringify %}
            {% types = ivar.type.union_types.reject { |type| type == ::Nil } %}
            {% converter = field && field[:converter] %}
            {% if converter %}
              {% writable = converter.is_a?(Path) && converter.resolve.class.methods.any? { |method| method.name == "to_yaml" && method.args.size == 2 } %}
              {% nested_section = false %}
            {% else %}
              {% nested_section = types.size == 1 && types[0] < ::YAML::Serializable %}
              {% writable = nested_section || types.all? do |type|
                   scalar = type <= ::String || type <= ::Bool || type < ::Int || type < ::Float || type <= ::Time || type < ::Enum
                   collection = (type <= ::Array || type <= ::Hash) &&
                                type.type_vars.all? { |inner| inner <= ::String || inner <= ::Bool || inner < ::Int || inner < ::Float }
                   scalar || collection
                 end %}
            {% end %}
            {% if writable %}
              %value{ivar.name} = instance.@{{ ivar.name.id }}
              unless %value{ivar.name}.nil?
                {{ key }}.to_yaml(builder)
                {% if converter %}
                  {{ converter }}.to_yaml(%value{ivar.name}, builder)
                {% elsif nested_section %}
                  write_every_field(%value{ivar.name}, builder)
                {% else %}
                  %value{ivar.name}.to_yaml(builder)
                {% end %}
              end
            {% end %}
          {% end %}
        {% end %}
      end
    end
  end
end

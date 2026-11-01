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
  end
end

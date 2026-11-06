module Amber::Schema
  # :nodoc:
  #
  # Reads the generic type names a schema field declares, such as
  # `"Array(Int32)"` or `"Hash(String, Bool)"`.
  module TypeNames
    # Returns the element type of an `Array(...)` type name (`"Int32"` for
    # `"Array(Int32)"`), or `nil` when *type_name* names no array.
    def self.array_element_type(type_name : String) : String?
      generic_argument(type_name, "Array(")
    end

    # Returns the value type of a `Hash(String, ...)` type name (`"Bool"`
    # for `"Hash(String, Bool)"`), or `nil` when *type_name* names no such
    # hash.
    def self.string_hash_value_type(type_name : String) : String?
      generic_argument(type_name, "Hash(String, ")
    end

    # The text between *opening* at the start of *type_name* and its final
    # `)`: at least one character, on one line.
    private def self.generic_argument(type_name : String, opening : String) : String?
      return unless type_name.starts_with?(opening) && type_name.ends_with?(')')

      argument = type_name[opening.size...-1]
      return if argument.empty? || argument.includes?('\n')
      argument
    end
  end
end

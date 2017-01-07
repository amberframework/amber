module Kemalyst::Generator
  class Field
    property name : String
    property type : String
    property cr_type : String
    property db_type : String

    def initialize(field)
      @name, @type = field.split(":")
      @cr_type, @db_type = cr_db_type(@type)
    end

    def cr_db_type(type = "string")
      @type = type.downcase
      case @type
      when "text"
        ["String","TEXT"]
      when "int", "integer"
        ["Int32", "INT"]
      when "float"
        ["Float32", "FLOAT"]
      when "real"
        ["Float64", "REAL"]
      when "bool", "boolean"
        ["Bool", "BOOL"]
      when "date"
        ["Time", "DATE"]
      when "time", "timestamp"
        ["Time", "TIMESTAMP"]
      else
        ["String", "VARCHAR"]
      end
    end
  end
end

module Kemalyst::Generator
  class Field
    property name : String
    property type : String
    property cr_type : String
    property db_type : String

    def initialize(field)
      field = "#{field}:string" unless field.includes? ":"
      @name, @type = field.split(":")
      @cr_type, @db_type = cr_db_type(@type)
    end

    def cr_db_type(type = "string")
      @type = type.downcase
      case @type
      when "text"
        ["String","TEXT"]
      when "int", "integer"
        @type = "integer"
        ["Int32", "INT"]
      when "float"
        ["Float32", "FLOAT"]
      when "real"
        ["Float64", "REAL"]
      when "bool", "boolean"
        @type = "boolean"
        ["Bool", "BOOL"]
      when "date"
        ["Time", "DATE"]
      when "time", "timestamp"
        @type = "time"
        ["Time", "TIMESTAMP"]
      else
        ["String", "VARCHAR"]
      end
    end
  end
end

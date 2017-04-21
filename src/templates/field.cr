module Kemalyst::Generator
  class Field
    TYPE_MAPPING = {
      mysql: {
        TIMESTAMP: "TIMESTAMP NULL",
        VARCHAR: "VARCHAR(255)"
      }
    }

    property name : String
    property type : String
    property cr_type : String
    property db_type : String
    property hidden : Bool
    @database : String

    def initialize(field, hidden = false, database = "pg")
      field = "#{field}:string" unless field.includes? ":"
      @name, @type = field.split(":")
      @cr_type, @db_type = cr_db_type(@type)
      @hidden = hidden
      @database = database
    end

    def cr_db_type(type = "string")
      @type = type.downcase
      case @type
      when "text"
        ["String", "TEXT"]
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

    def db_mapped_type
      if (tm = TYPE_MAPPING[@database]?)
        tm[@db_type]? || @db_type
      else
        @db_type
      end
    end
  end
end

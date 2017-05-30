module Amber::CMD
  class Field
    TYPE_MAPPING = {
      common: {
        string:    ["string", "String", "VARCHAR"],
        text:      ["text", "String", "TEXT"],
        int:       ["integer", "Int32", "INT"],
        int32:     ["integer", "Int32", "INT"],
        integer:   ["integer", "Int32", "INT"],
        int64:     ["bigint", "Int64", "BIGINT"],
        bigint:    ["bigint", "Int64", "BIGINT"],
        float:     ["float", "Float32", "FLOAT"],
        real:      ["real", "Float64", "REAL"],
        bool:      ["boolean", "Bool", "BOOL"],
        boolean:   ["boolean", "Bool", "BOOL"],
        date:      ["date", "Time", "DATE"],
        time:      ["time", "Time", "TIMESTAMP"],
        timestamp: ["time", "Time", "TIMESTAMP"],
      },
      mysql: {
        string:    ["string", "String", "VARCHAR(255)"],
        time:      ["time", "Time", "TIMESTAMP NULL"],
        timestamp: ["time", "Time", "TIMESTAMP NULL"],
      },
      sqlite: {
        int:       ["bigint", "Int64", "INT"],
        int32:     ["bigint", "Int64", "INT"],
        integer:   ["bigint", "Int64", "INT"],
        int64:     ["bigint", "Int64", "INT"],
        bigint:    ["bigint", "Int64", "INT"],
        bool:      ["bool_as_int", "Int64", "BOOL"],
        boolean:   ["bool_as_int", "Int64", "BOOL"],
        date:      ["date_as_var", "String", "DATE"],
        time:      ["time_as_var", "String", "TIMESTAMP"],
        timestamp: ["time_as_var", "String", "TIMESTAMP"],
      },
    }

    property name : String
    property type : String
    property cr_type : String
    property db_type : String
    property hidden : Bool
    property database : String

    def initialize(field, hidden = false, database = "pg")
      field = "#{field}:string" unless field.includes? ":"
      @name, @type = field.split(":")
      @database = database
      @type, @cr_type, @db_type = type_mapping(@type.downcase)
      @hidden = hidden
    end

    def type_mapping(type = "string")
      if type_mapping = TYPE_MAPPING[@database]?
        if mapping = type_mapping[@type]?
          return mapping
        end
      end
      if mapping = TYPE_MAPPING["common"][@type]?
        return mapping
      else
        raise "type #{@type} not available"
      end
    end

  end
end

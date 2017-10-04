module Amber::CLI
  class Field
    TYPE_MAPPING = {
      common: {
        string:     ["string", "String", "VARCHAR"],
        text:       ["text", "String", "TEXT"],
        int:        ["integer", "Int32", "INT"],
        int32:      ["integer", "Int32", "INT"],
        integer:    ["integer", "Int32", "INT"],
        int64:      ["bigint", "Int64", "BIGINT"],
        bigint:     ["bigint", "Int64", "BIGINT"],
        float:      ["float", "Float32", "FLOAT"],
        float64:    ["real", "Float64", "FLOAT"],
        real:       ["real", "Float64", "REAL"],
        bool:       ["boolean", "Bool", "BOOL"],
        boolean:    ["boolean", "Bool", "BOOL"],
        date:       ["date", "Time", "DATE"],
        time:       ["time", "Time", "TIMESTAMP"],
        timestamp:  ["time", "Time", "TIMESTAMP"],
        password:   ["password", "String", "VARCHAR"],
        ref:        ["reference", "Int64", "BIGINT"],
        belongs_to: ["reference", "Int64", "BIGINT"],
        reference:  ["reference", "Int64", "BIGINT"],
        references: ["reference", "Int64", "BIGINT"],
      },
      mysql: {
        string:    ["string", "String", "VARCHAR(255)"],
        password:  ["password", "String", "VARCHAR(255)"],
        time:      ["time", "Time", "TIMESTAMP NULL"],
        timestamp: ["time", "Time", "TIMESTAMP NULL"],
      },
      sqlite: {
        int:       ["bigint", "Int64", "INT"],
        int32:     ["bigint", "Int64", "INT"],
        integer:   ["bigint", "Int64", "INT"],
        int64:     ["bigint", "Int64", "INT"],
        bigint:    ["bigint", "Int64", "INT"],
        bool:      ["boolean", "Int64", "BOOL"],
        boolean:   ["boolean", "Int64", "BOOL"],
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

    def reference?
      self.type == "reference"
    end
  end
end

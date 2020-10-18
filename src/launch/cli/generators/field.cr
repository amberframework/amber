module Launch::CLI
  class Field
    TYPE_MAPPING = {
      common: {
        string:     ["string", "String", "string"],
        text:       ["text", "String", "text"],
        int:        ["integer", "Int32", "integer"],
        int32:      ["integer", "Int32", "integer"],
        integer:    ["integer", "Int32", "integer"],
        int64:      ["bigint", "Int64", "bigint"],
        bigint:     ["bigint", "Int64", "bigint"],
        float:      ["float", "Float64", "float"],
        float64:    ["real", "Float64", "double"],
        real:       ["real", "Float64", "REAL"],
        bool:       ["boolean", "Bool", "BOOL"],
        boolean:    ["boolean", "Bool", "BOOL"],
        date:       ["date", "Time", "date"],
        time:       ["time", "Time", "timestamp"],
        timestamp:  ["time", "Time", "timestamp"],
        ref:        ["reference", "Int64", "reference"],
        belongs_to: ["reference", "Int64", "reference"],
        reference:  ["reference", "Int64", "reference"],
        references: ["reference", "Int64", "reference"],
        # TODO: Add more jennifer methods
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
        mapping
      else
        raise "type #{@type} not available"
      end
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "name", name
        json.field "type", type
        json.field "cr_type", cr_type
        json.field "db_type", db_type
        json.field "hidden", hidden
        json.field "database", database
      end
      json.to_s
    end

    def reference?
      self.type == "reference"
    end

    def class_name
      Inflector.classify(@name)
    end
  end
end

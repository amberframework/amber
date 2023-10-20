module Amber
  class Config
    class_property data = ConfigData.new(Hash(String, String | Int32 | JSON::Any | ConfigData).new)
  end

  struct ConfigData
    property data : Hash(String, String | Int32 | JSON::Any | self)

    def initialize(@data)
    end
  end
end

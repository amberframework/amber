require "yaml"

module Amber::Configuration
  class DatabaseConfig
    include YAML::Serializable

    property url : String = ""

    def initialize
    end
  end
end

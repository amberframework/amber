require "yaml"

module Amber::Configuration
  class PubSubConfig
    include YAML::Serializable

    property adapter : String = "memory"

    def initialize
    end
  end
end

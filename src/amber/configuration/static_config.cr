require "yaml"

module Amber::Configuration
  class StaticConfig
    include YAML::Serializable

    property headers : Hash(String, String) = {} of String => String

    def initialize
    end
  end
end

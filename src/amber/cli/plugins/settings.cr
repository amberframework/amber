require "yaml"

module Amber::Plugins
  class Settings
    include YAML::Serializable

    alias RouteType = Hash(String, Hash(String, Array(String)))

    property routes = RouteType{"pipelines" => Hash(String, Array(String)).new,
                                "plugs"     => Hash(String, Array(String)).new}
    property args = [] of String
  end
end

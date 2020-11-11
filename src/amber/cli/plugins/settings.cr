require "yaml"
require "yaml_mapping"

module Amber::Plugins
  class Settings
    alias RouteType = Hash(String, Hash(String, Array(String)))

    YAML.mapping(
      routes: {
        type:    RouteType,
        default: {
          "pipelines" => Hash(String, Array(String)).new,
          "plugs"     => Hash(String, Array(String)).new,
        },
      },
      args: {
        type:    Array(String),
        default: [] of String,
      }
    )
  end
end

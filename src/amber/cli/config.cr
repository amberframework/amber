require "yaml_mapping"

module Amber::CLI
  def self.config
    if File.exists? AMBER_YML
      begin
        Config.from_yaml File.read(AMBER_YML)
      rescue ex : YAML::ParseException
        Log.error(exception: ex) { "Couldn't parse #{AMBER_YML} file" }
        exit 1
      end
    else
      Config.new
    end
  end

  class Config
    SHARD_YML    = "shard.yml"
    DEFAULT_NAME = "[process_name]"

    # see defaults below
    alias WatchOptions = Hash(String, Hash(String, Array(String)))

    property database : String = "pg"
    property language : String = "slang"
    property model : String = "granite"
    property recipe : (String | Nil) = nil
    property recipe_source : (String | Nil) = nil
    property watch : WatchOptions
    property minimal : Bool = false

    def initialize
      @watch = default_watch_options
    end

    YAML.mapping(
      database: {type: String, default: "pg"},
      language: {type: String, default: "slang"},
      model: {type: String, default: "granite"},
      recipe: String | Nil,
      recipe_source: String | Nil,
      watch: {type: WatchOptions, default: default_watch_options}
    )

    def default_watch_options
      appname = self.class.get_name
      options = WatchOptions{
        "run" => Hash{
          "build_commands" => [
            "mkdir -p bin",
            "crystal build ./src/#{appname}.cr -o bin/#{appname}",
          ],
          "run_commands" => [
            "bin/#{appname}",
          ],
          "include" => [
            "./config/**/*.cr",
            "./src/**/*.cr",
            "./src/views/**/*.slang",
          ],
        },
      }
      add_npm_watch_options(options)
    end

    def add_npm_watch_options(options)
      return options if @minimal
      options["npm"] = Hash{
        "build_commands" => [
          "npm install --loglevel=error",
        ],
        "run_commands" => [
          "npm run watch",
        ],
      }
      options
    end

    def self.get_name
      if File.exists?(SHARD_YML) &&
         (yaml = YAML.parse(File.read SHARD_YML)) &&
         (name = yaml["name"]?)
        name.as_s
      else
        DEFAULT_NAME
      end
    end
  end
end

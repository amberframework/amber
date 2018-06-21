require "yaml"

module Amber::CLI
  def self.config
    if File.exists? AMBER_YML
      Config.from_yaml File.read(AMBER_YML)
    else
      Config.new
    end
  rescue ex : YAML::ParseException
    logger.error "Couldn't parse #{AMBER_YML} file", "Watcher", :red
    exit 1
  end

  def generate_config
    File.write(AMBER_YML, CLI.config.to_yaml)
  end

  class Config
    alias Watch = Hash(String, Hash(String, Array(String)))

    getter database : String = "pg"
    getter language : String = "slang"
    getter model : String = "granite"
    getter recipe : String?
    getter recipe_source : String?
    getter watch : Watch = {
      "server" => {
        "files" => [
          "src/**/*.cr",
          "src/**/*.#{@language}",
          "config/**/*.cr"
        ],
        "commands" => [
          "shards build -p --no-color",
          "bin/#{app_name}"
        ]
      }
    }

    def initialize
    end

    private def app_name
      File.basename(Dir.current)
    end

    YAML.mapping(
      database: {type: String, default: @database},
      language: {type: String, default: @language},
      model: {type: String, default: @model},
      recipe: String?,
      recipe_source: String?,
      watch: {type: Watch, default: @watch}
    )
  end
end

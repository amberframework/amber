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

  class Config
    alias Watch = Hash(String, Hash(String, Array(String)))

    getter database : String = "pg"
    getter language : String = "slang"
    getter model : String = "granite"
    getter recipe : String?
    getter recipe_source : String?
    getter watch : Watch?

    def initialize
    end

    YAML.mapping(
      database: {type: String, default: "pg"},
      language: {type: String, default: "slang"},
      model: {type: String, default: "granite"},
      recipe: String?,
      recipe_source: String?,
      watch: Watch?
    )
  end
end

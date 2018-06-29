module Amber::CLI
  def self.config
    if File.exists? AMBER_YML
      Config.from_yaml File.read(AMBER_YML)
    else
      Config.new
    end
  end

  class Config
    property database : String = "pg"
    property language : String = "slang"
    property model : String = "granite"
    property api_only : Bool = false
    property recipe : (String | Nil) = nil
    property recipe_source : (String | Nil) = nil

    def initialize
    end

    YAML.mapping(
      database: {type: String, default: "pg"},
      language: {type: String, default: "slang"},
      model: {type: String, default: "granite"},
      api_only: {type: Bool, default: false},
      recipe: String | Nil,
      recipe_source: String | Nil
    )
  end
end

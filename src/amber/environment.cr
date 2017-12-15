require "./environment/**"
require "./support/file_encryptor"

module Amber::Environment
  alias EnvType = String | Symbol

  macro included
    AMBER_ENV = "AMBER_ENV"

    class_property environment_path : String = "./config/environments/"
    @@settings : Settings?
    Colorize.enabled = settings.logging["color"]

    def self.settings
	   @@settings ||= Loader.new(env.to_s, environment_path).settings
    end

    def self.logger
      settings.logger
    end

    def self.env=(env : EnvType)
      ENV[AMBER_ENV] = env.to_s
	    @@env =  Env.new(env.to_s)
      @@settings = Loader.new(env.to_s, environment_path).settings
    end

    def self.env
	    current_environment = ENV[AMBER_ENV]? || "development"
      @@env ||= Env.new(current_environment)
    end
  end
end

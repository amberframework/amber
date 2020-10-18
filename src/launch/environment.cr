require "./environment/**"
require "./support/file_encryptor"

module Launch::Environment
  alias EnvType = String | Symbol

  macro included
    class_property path : String = "./config/environments/"
    @@settings : Settings?
    @@credentials : YAML::Any?

    def self.settings
      @@settings ||= Loader.new(env.to_s, path).settings
      # Dont rescue errors if environment yml doesn't exist.
      # rescue Launch::Exceptions::Environment
      #   @@settings = Settings.from_yaml("default: settings")
    end

    def self.credentials
      @@credentials ||= Loader.new(env.to_s, path).credentials
    end

    def self.env=(env : EnvType)
      @@env = Env.new(env.to_s)
      @@settings = Loader.new(env, path).settings
    end

    def self.env
      @@env ||= Env.new
    end
  end
end

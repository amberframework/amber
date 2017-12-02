require "./environment/**"
require "./support/file_encryptor"

module Amber::Environment
  alias EnvType = String | Symbol

  macro included
    SECRET_KEY  = "AMBER_ENCRYPTION_KEY"
    SECRET_FILE = "./.encryption_key"
    CURRENT_ENVIRONMENT = ENV["AMBER_ENV"] ||= "development"
    class_property environment_path : String = "./config/environments/"

    @@_settings : Settings?

    def self.settings
      @@_settings ||= Loader.new(CURRENT_ENVIRONMENT, @@environment_path, file_encryptor).settings
    end

    def self.logger
      settings.logger
    end

    def self.env=(env : EnvType)
      ENV["AMBER_ENV"] = env.to_s
      @@_settings = Loader.new(env, @@environment_path, file_encryptor).settings
    end

    def self.env
      @@env ||= Env.new(CURRENT_ENVIRONMENT)
    end

    def self.file_encryptor
      @@file_encryptor ||= Support::FileEncryptor.new(encryption_key)
    end

    private def self.encryption_key
      ENV[SECRET_KEY]? || File.open(SECRET_FILE).gets_to_end.to_s
    end
  end
end

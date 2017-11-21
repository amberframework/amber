module Amber
  SECRET_KEY          = "AMBER_SECRET_KEY"
  SECRET_FILE         = "./.amber_secret_key"
  class_property environment_path = "./config/environments/"
  CURRENT_ENVIRONMENT = ENV["AMBER_ENV"] ||= "development"

  def self.settings
    EnvironmentLoader.new(CURRENT_ENVIRONMENT, @@environment_path).settings
  end

  def self.env=(env : EnvType)
    ENV["AMBER_ENV"] = env.to_s
    Amber::Server.settings = EnvironmentLoader.new(env, @@environment_path).settings
  end

  def self.secret_key
    ENV[SECRET_KEY]? || begin
      File.open(SECRET_FILE).gets_to_end.to_s if File.exists?(SECRET_FILE)
    end
  end

  class EnvironmentLoader
    def initialize(@environment : Amber::EnvType, @path : String)
      raise Exceptions::Environment.new(@path, @environment) unless settings_file_exist?
    end

    def settings
      Amber::Settings.from_yaml(settings_content.to_s)
    end

    private def settings_file_exist?
      File.exists?(yml_settings_file) || File.exists?(enc_settings_file)
    end

    private def settings_content
      if File.exists?(yml_settings_file)
        File.read(yml_settings_file)
      elsif File.exists?(enc_settings_file)
        content = File.open(enc_settings_file).gets_to_end.to_slice
        decrypt_contents(content)
      end
    end

    private def decrypt_contents(content)
      decryptor = Amber::Support::MessageEncryptor.new(Amber.secret_key.not_nil!)
      String.new(decryptor.decrypt(content))
    end

    private def yml_settings_file
      @yml_settings ||= "#{@path}#{@environment}.yml"
    end

    private def enc_settings_file
      @enc_settings ||= "#{@path}.#{@environment}.enc"
    end
  end
end

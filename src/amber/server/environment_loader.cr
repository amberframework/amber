require "./settings"

module Amber
  class EnvironmentLoader
    # TODO: Should probably use Amber::Env type here but can't until we refactor the Amber module.
    # Should default path to Amber.environment_path
    def initialize(@environment : String | Symbol = :development, @path : String = "./config/environments")
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
        Support::FileEncryptor.read_as_string(enc_settings_file)
      end
    end

    private def yml_settings_file
      @yml_settings ||= "#{@path}/#{@environment}.yml"
    end

    private def enc_settings_file
      @enc_settings ||= "#{@path}/.#{@environment}.enc"
    end
  end
end

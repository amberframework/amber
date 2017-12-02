module Amber::Environment
  class Loader
    def initialize(@environment : Amber::Environment::EnvType = Amber.env.to_s,
                   @path : String = Amber.environemnt_path)
      raise Exceptions::Environment.new(@path, @environment) unless settings_file_exist?
    end

    def settings
      Settings.from_yaml(settings_content.to_s)
    end

    private def settings_content
      if File.exists?(yml_settings_file)
        File.read(yml_settings_file)
      elsif File.exists?(enc_settings_file)
        Support::FileEncryptor.read_as_string(enc_settings_file)
      end
    end

    private def yml_settings_file
      @yml_settings ||= File.expand_path("#{@path}/#{@environment}.yml")
    end

    private def enc_settings_file
      @enc_settings ||= File.expand_path("#{@path}/.#{@environment}.enc")
    end

    private def settings_file_exist?
      File.exists?(yml_settings_file) || File.exists?(enc_settings_file)
    end
  end
end

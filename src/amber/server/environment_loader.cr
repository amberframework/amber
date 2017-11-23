module Amber
  class EnvironmentLoader
    def initialize(@environment : Amber::EnvType, @path : String)
      raise Exceptions::Environment.new(expanded_path, @environment) unless settings_file_exist?
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
      @yml_settings ||= "#{expanded_path}#{@environment}.yml"
    end

    private def enc_settings_file
      @enc_settings ||= "#{expanded_path}.#{@environment}.enc"
    end

    private def expanded_path
      File.expand_path(@path) + "/"
    end
  end
end

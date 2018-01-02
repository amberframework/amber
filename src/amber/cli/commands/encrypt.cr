module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "e", aliased: "encrypt"

    class Encrypt < Command
      class Options
        arg "env", desc: "environment file to encrypt", default: "production"
        string ["-e", "--editor"], desc: "Prefered Editor: [vim, nano, pico, etc]", default: "vim"
        bool ["--noedit"], desc: "Skip editing and just encrypt", default: false
        help
      end

      class Help
        header "Encrypts environment YAML file."
        caption "# Encrypts environment YAML file. [env | -e --editor | --noedit]"
      end

      def run
        env = args.env
        encrypted_file = "config/environments/.#{env}.enc"
        unencrypted_file = "config/environments/#{env}.yml"

        unless File.exists?(unencrypted_file) || File.exists?(encrypted_file)
          raise Exceptions::Environment.new("./config/environments/", env)
        end

        if File.exists?(encrypted_file)
          File.write(unencrypted_file, Support::FileEncryptor.read(encrypted_file))
          system("#{options.editor} #{unencrypted_file}") unless options.noedit?
        end

        if File.exists?(unencrypted_file)
          Support::FileEncryptor.write(encrypted_file, File.read(unencrypted_file))
          File.delete(unencrypted_file)
        end
      rescue e : Exception
        exit! e.message, error: true
      end
    end
  end
end

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "e", aliased: "encrypt"

    class Encrypt < ::Cli::Command
      class Options
        arg "env", desc: "environment file to encrypt", default: "production"
        string ["-e", "--editor"], desc: "Prefered Editor: [vim, nano, pico, etc]", default: "vim"
        bool ["--noedit"], desc: "Skip editing and just encrypt", default: false
        help
      end

      class Help
        caption "# Encrypts Environment"
      end

      def run
        env = args.env
        encrypted_file = "config/environments/.#{env}.enc"
        unencrypted_file = "config/environments/#{env}.yml"

        if File.exists?(encrypted_file)
          File.write(unencrypted_file, Support::FileEncryptor.read(encrypted_file))
          system("#{options.editor} #{unencrypted_file}") unless options.noedit?
        end

        if File.exists?(unencrypted_file)
          Support::FileEncryptor.write(encrypted_file, File.read(unencrypted_file))
          File.delete(unencrypted_file)
        else
          puts "#{env}.yml doesn't exist. Loading defaults!"
        end
      rescue
        puts "Failed! Make sure to set AMBER_ENCRYPTION_KEY env or add hidden file .encryption_key"
      end
    end
  end
end

require "cli"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "ex", aliased: "exec"

    class Exec < ::Cli::Command
      command_name "exec"

      class Options
        arg "code", desc: "Crystal code or .cr file to execute within the application scope", required: false, default: nil
        string ["-e", "--editor"], desc: "Prefered editor: [vim, nano, pico, etc], only used when no code or .cr file is specified", default: "vim"
        string ["-b", "--back"], desc: "Runs prevous command files 'amber exec'", default: "0"
      end

      class Help
        caption "# It runs Crystal code within the application scope"
      end

      def run
        result = ""
        if args.size > 0 && args.code
          if args.code.ends_with?(".cr") && File.exists?(args.code)
            result = `crystal eval 'require "../config/*"; require "./#{args.code}"'`
          else
            result = `crystal eval 'require "../config/*"; puts (#{args.code}).inspect'`
          end
        else
          Dir.mkdir("tmp") unless Dir.exists?("tmp")
          filename = "./tmp/console_#{Time.now.epoch}.cr"
          if options.back.to_i(strict: false) > 0
            old_filename = Dir.glob("./tmp/console_*.cr").reverse[options.back.to_i(strict: false) - 1]
            system("cp #{old_filename} #{filename}")
          end
          system("#{options.editor} #{filename}")
          if File.exists?(filename)
            result = `crystal eval 'require "../config/*"; require "#{filename}"'`
          end
        end
        if result.includes?("Error in line 1:") &&
           result.includes?("while requiring \"../config/*\": can't find file '../config/*' relative to '.'")
          result = "error: 'amber exec' can only be used from the root of a valid amber project"
        end
        puts result
        result
      end
    end
  end
end

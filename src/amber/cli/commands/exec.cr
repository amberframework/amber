require "cli"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "e", aliased: "exec"

    class Exec < ::Cli::Command
      command_name "exec"

      class Options
        arg "code", desc: "Crystal code or .cr file to execute within the application scope", required: false, default: nil
        string ["-e", "--editor"], desc: "Prefered editor: [vim, nano, pico, etc], only used when no code or .cr file is specified", default: "vim"
        bool ["-p", "--persist"], desc: "Persist the code across invocations of 'amber exec'"
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
          system("#{options.editor} .amber_exec.cr")
          if File.exists?(".amber_exec.cr")
            result = `crystal eval 'require "../config/*"; require "./.amber_exec.cr"'`
            File.delete(".amber_exec.cr") unless options.persist?
          end
        end
        if result.includes?("Error in line 1:") &&
           result.includes?("while requiring \"../config/*\": can't find file '../config/*' relative to '.'")
          puts "error: 'amber exec' can only be used within the root of a valid amber project"
        else
          puts result
        end
      end
    end
  end
end

require "cli"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "x", aliased: "exec"

    class Exec < ::Cli::Command
      command_name "exec"
      @filename = "./tmp/console_#{Time.now.epoch}.cr"
      @result : String? = nil

      class Options
        arg "code", desc: "Crystal code or .cr file to execute within the application scope", default: ""
        string ["-e", "--editor"], desc: "Prefered editor: [vim, nano, pico, etc], only used when no code or .cr file is specified", default: "vim"
        string ["-b", "--back"], desc: "Runs prevous command files: 'amber exec -b [times_ago]'", default: "0"
      end

      class Help
        caption "# It runs Crystal code within the application scope"
      end

      def run
        unless args.code.blank? || File.exists?(args.code)
          @result = `crystal eval 'require "../config/*"; puts (#{args.code}).inspect'`
        else
          prepare_file
          system("#{options.editor} #{@filename}")
          @result = `crystal eval 'require "../config/*"; require "#{@filename}"'` if File.exists?(@filename)
        end

        if @result && @result.not_nil!.includes?("while requiring \"../config/*\": can't find file '../config/*' relative to '.'")
          @result = "Error: 'amber exec' can only be used from the root of a valid amber project"
        end
        puts @result
        @result
      end

      def prepare_file
        _filename = if File.exists?(args.code)
                      args.code
                    elsif options.back.to_i(strict: false) > 0 
                      Dir.glob("./tmp/console_*.cr").reverse[options.back.to_i(strict: false) - 1]?
                    end

        system("cp #{_filename} #{@filename}") if _filename
        @filename
      end
    end
  end
end

require "cli"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "x", aliased: "exec"

    class Exec < Command
      command_name "exec"
      @filename = "./tmp/#{Time.now.epoch_ms}_console.cr"

      class Options
        arg "code", desc: "Crystal code or .cr file to execute within the application scope", default: ""
        string ["-e", "--editor"], desc: "Prefered editor: [vim, nano, pico, etc], only used when no code or .cr file is specified", default: "vim"
        string ["-b", "--back"], desc: "Runs previous command files: 'amber exec -b [times_ago]'", default: "0"
        help
      end

      class Help
        caption "# It runs Crystal code within the application scope"
      end

      def prepare_file
        _filename = if File.exists?(args.code)
                      args.code
                    elsif options.back.to_i(strict: false) > 0
                      Dir.glob("./tmp/*_console.cr").sort.reverse[options.back.to_i(strict: false) - 1]?
                    end

        system("cp #{_filename} #{@filename}") if _filename
      end

      def run
        Dir.mkdir("tmp") unless Dir.exists?("tmp")

        unless args.code.blank? || File.exists?(args.code)
          File.write(@filename, "puts (#{args.code}).inspect")
        else
          prepare_file
          system("#{options.editor} #{@filename}")
        end

        result = ""
        if File.exists?(@filename)
          eval_cmd = Array(String).new
          eval_cmd << %(require "./config/application.cr";) if Dir.exists?("config")
          eval_cmd << %(require "#{@filename}";)
          result = `crystal eval '#{eval_cmd.join(" ")}'`
        end

        File.write(@filename.sub("console.cr", "console_result.log"), result) unless result.blank?
        puts result, "Exec"
      end
    end
  end
end

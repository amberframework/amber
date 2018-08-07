require "cli"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "x", aliased: "exec"

    class Exec < Command
      command_name "exec"
      @filename : String
      @filelogs : String

      def initialize(__previous, __argv)
        @filename = "./tmp/#{Time.now.epoch_ms}_console.cr"
        @filelogs = @filename.sub("console.cr", "console_result.log")
        super(__previous, __argv)
      end

      class Options
        arg "code", desc: "Crystal code or .cr file to execute within the application scope", default: ""
        string ["-e", "--editor"], desc: "Preferred editor: [vim, nano, pico, etc], only used when no code or .cr file is specified", default: "vim"
        string ["-b", "--back"], desc: "Runs previous command files: 'amber exec -b [times_ago]'", default: "0"
        bool "--no-color", desc: "Disable colored output", default: false
        help
      end

      class Help
        header "Executes Crystal code within the application scope"
        caption "# Executes Crystal code within the application scope"
      end

      private def prepare_file
        _filename = if File.exists?(args.code)
                      args.code
                    elsif options.back.to_i(strict: false) > 0
                      Dir.glob("./tmp/*_console.cr").sort.reverse[options.back.to_i(strict: false) - 1]?
                    end

        system("cp #{_filename} #{@filename}") if _filename
      end

      private def show
        File.open(@filelogs, "r") do |file|
          loop do
            output = file.gets_to_end
            puts output unless output.empty?
            sleep 1.millisecond
          end
        end
      end

      private def execute(code)
        file = File.open(@filelogs, "w")
        spawn show
        process = Process.run(code, shell: true, output: file, error: file)
        process.exit_status
      end

      private def wrap(code)
        <<-CRYSTAL
        result = (
          #{code}
        )
        puts result.inspect
        CRYSTAL
      end

      def run
        CLI.toggle_colors(options.no_color?)
        exit_code = 0
        Dir.mkdir("tmp") unless Dir.exists?("tmp")

        if args.code.blank? || File.exists?(args.code)
          prepare_file
          system("#{options.editor} #{@filename}")
        else
          File.write(@filename, wrap(args.code))
        end

        if File.exists?(@filename)
          code = [] of String
          code << %(require "./config/application.cr") if Dir.exists?("config")
          code << %(require "#{@filename}")
          exit_code = execute(%(crystal eval '#{code.join("\n")}'))
        end

        unless exit_code.zero?
          puts File.read(@filename)
          exit! error: true, code: exit_code
        end
      end
    end
  end
end

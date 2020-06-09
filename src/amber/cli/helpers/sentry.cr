require "cli"
require "yaml"
require "./process_runner"

module Sentry
  class SentryCommand < Cli::Command
    command_name "sentry"

    class Options
      def self.defaults
        name = Amber::CLI::Config.get_name
        {
          name:         name,
          process_name: "./bin/#{name}",
          build:        join_commands(Amber::CLI.config.watch["run"]["build_commands"]),
          run:          join_commands(Amber::CLI.config.watch["run"]["run_commands"]),
          watch:        Amber::CLI.config.watch["run"]["include"],
        }
      end

      string %w(-n --name), desc: "Sets the name of the app process",
        default: Options.defaults[:name]

      string %w(-b --build), desc: "Overrides the default build command",
        default: Options.defaults[:build]

      string %w(-r --run), desc: "Overrides the default run command",
        default: Options.defaults[:run]

      array %w(-w --watch),
        desc: "Overrides default files and appends to list of watched files",
        default: Options.defaults[:watch]

      bool %w(-i --info),
        desc: "Shows the values for build/run commands, and watched files",
        default: false

      help

      def self.join_commands(command_array : Array(String)) : String
        case command_array.size
        when 0 then "echo"
        when 1 then command_array.first
        else
          command_array.map { |c| "(#{c})" }.join(" && ")
        end
      end
    end

    def run
      if options.info?
        puts <<-INFO
          name:       #{options.name?}
          build:      #{options.build?}
          run:        #{options.run?}
          files:      #{options.watch}
        INFO
        exit! code: 0
      end

      build_commands = Hash(String, String).new
      run_commands = Hash(String, String).new
      includes = Hash(String, Array(String)).new
      excludes = Hash(String, Array(String)).new
      Amber::CLI.config.watch.each do |task, opts|
        build_commands[task] = Options.join_commands(opts["build_commands"]) if opts.has_key?("build_commands")
        run_commands[task] = Options.join_commands(opts["run_commands"]) if opts.has_key?("run_commands")
        includes[task] = opts["include"] if opts.has_key?("include")
        excludes[task] = opts["exclude"] if opts.has_key?("exclude")

        if task == "run" # can override via command line args
          build_commands[task] = options.build
          run_commands[task] = options.run
          includes[task] = options.watch
        end
      end
      process_runner = Sentry::ProcessRunner.new(
        process_name: options.name,
        build_commands: build_commands,
        run_commands: run_commands,
        includes: includes,
        excludes: excludes
      )

      process_runner.run
    end
  end
end

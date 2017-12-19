require "cli"
require "yaml"
require "./process_runner"

module Sentry
  class SentryCommand < Cli::Command
    command_name "sentry"
    SHARD_YML    = "shard.yml"
    DEFAULT_NAME = "[process_name]"

    class Options
      def self.defaults
        name = Options.get_name
        {
          name:         name,
          process_name: "./bin/#{name}",
          build:        "mkdir -p bin && crystal build ./src/#{name}.cr -o bin/#{name}",
          watch:        ["./src/**/*.cr", "./src/**/*.ecr"],
        }
      end

      def self.get_name
        if File.exists?(SHARD_YML) &&
           (yaml = YAML.parse(File.read SHARD_YML)) &&
           (name = yaml["name"]?)
          name.as_s
        else
          DEFAULT_NAME
        end
      end

      string %w(-n --name), desc: "Sets the name of the app process",
        default: Options.defaults[:name]

      string %w(-b --build), desc: "Overrides the default build command",
        default: Options.defaults[:build]

      string "--build-args", desc: "Specifies arguments for the build command"

      string %w(-r --run), desc: "Overrides the default run command",
        default: Options.defaults[:process_name]

      string "--run-args", desc: "Specifies arguments for the run command"

      array %w(-w --watch),
        desc: "Overrides default files and appends to list of watched files",
        default: Options.defaults[:watch]

      bool %w(-i --info),
        desc: "Shows the values for build/run commands, build/run args, and watched files",
        default: false

      help
    end

    def run
      if options.info?
        puts <<-INFO
          name:       #{options.name?}
          build:      #{options.build?}
          build args: #{options.build_args?}
          run:        #{options.run?}
          run args:   #{options.run_args?}
          files:      #{options.watch}
        INFO
        exit! code: 0
      end

      build_args = if ba = options.build_args?
                     ba.split " "
                   else
                     [] of String
                   end
      run_args = if ra = options.run_args?
                   ra.split " "
                 else
                   [] of String
                 end

      process_runner = Sentry::ProcessRunner.new(
        process_name: options.name,
        build_command: options.build,
        run_command: options.run,
        build_args: build_args,
        run_args: run_args,
        files: options.watch,
        logger: Amber::CLI.logger
      )

      process_runner.run
    end
  end
end

require "cli"

module Kemalyst::Generator

  class MainCommand < Cli::Supercommand
    command "w", aliased: "watch"

    class Watch < Cli::Command

      SENTRY = "./sentry"
      BUILD_CMD = "crystal build ./src/[app_name].cr"
      RUN_CMD = "./[app_name]"
      FILES = ["./src/**/*.cr", "./src/**/*.ecr", "./config/**/*.cr"]

      class Options

        string %w(-b --build), desc: "Overrides the default build command",
        default: BUILD_CMD

        string "--build-args", desc: "Specifies arguments for the build command"

        string %w(-r --run), desc: "Overrides the default run command",
        default: RUN_CMD

        string "--run-args", desc: "Specifies arguments for the run command"

        bool %w(-i --info),
        desc: "Shows the values for build/run commands, build/run args, \
and watched files"

        array %w(-w --watch),
        desc: "Overrides default files and appends to list of watched files",
        default: FILES

        help
      end

      def sentry?
        File.exists? SENTRY
      end

      def print_info
        puts "
      build:      #{options.build?}
      build args: #{options.build_args?}
      run:        #{options.run?}
      run args:   #{options.run_args?}
      files:      #{options.w}
    "
      end

      def run

        if options.i?
          print_info
          exit! code: 0
        end

        error! "Sentry not detected." unless sentry?

        command = SENTRY
        args = [] of String
        if options.build? && options.build != BUILD_CMD
          args << "-b"
          args << options.build
        end

        if options.build_args?
          args << "--build-args"
          args << options.build_args
        end

        if options.run? && options.run != RUN_CMD
          args << "-r"
          args << options.run
        end

        if options.run_args?
          args << "--run-args"
          args << options.run_args
        end

        options.w.each do |w|
          args << "-w"
          args << w
        end

        Process.exec(SENTRY, args, shell: true)

      end

    end

  end

end

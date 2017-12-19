require "sentry"

module Sentry
  class ProcessRunner
    property processes = [] of Process
    property process_name : String
    property files = [] of String
    @logger : Amber::Environment::Logger

    def initialize(
                   @process_name : String,
                   @build_command : String,
                   @run_command : String,
                   @build_args : Array(String) = [] of String,
                   @run_args : Array(String) = [] of String,
                   files = [] of String,
                   @logger = Amber::CLI.logger)
      @files = files
    end

    def run
      loop do
        scan_files
        sleep 1
      end
    end

    # Compiles and starts the application
    #
    def start_app
      stop_all_processes
      start_all_processes
    end

    private def scan_files
      file_changed = false

      Dir.glob(files) do |file|
        timestamp = get_timestamp(file)
        if FILE_TIMESTAMPS[file]? && FILE_TIMESTAMPS[file] != timestamp
          FILE_TIMESTAMPS[file] = timestamp
          file_changed = true
          log "#{file.capitalize.colorize(:light_gray)}"
        elsif FILE_TIMESTAMPS[file]?.nil?
          FILE_TIMESTAMPS[file] = timestamp
          file_changed = true
          log "Watching file: #{file.capitalize.colorize(:light_gray)}"
        end
      end

      start_app if (file_changed)
    end

    private def start_all_processes
      log "Compiling #{project_name}..."
      create_all_processes
    end

    private def stop_all_processes
      log "Terminating app #{project_name}..."
      @processes.each do |process|
        process.kill unless process.terminated?
      end
      processes.clear
    end

    private def create_all_processes
      build_app_process
      @processes << create_watch_process
      sleep 3
      create_npm_process
    end

    private def build_app_process
      log "Building project #{project_name}..."
      Process.run(@build_command, shell: true, output: true, error: true)
    end

    private def create_watch_process
      log "Starting #{project_name}..."
      Process.new(@run_command, output: true, error: true)
    end

    private def create_npm_process
      node_log "Installing dependencies..."
      Process.new("npm install && npm run watch", output: false, error: true, shell: true)
      node_log "Watching public directory"
    end

    private def get_timestamp(file : String)
      File.stat(file).mtime.to_s("%Y%m%d%H%M%S")
    end

    private def project_name
      process_name.capitalize.colorize(:white)
    end

    private def log(msg)
      @logger.puts msg, "Watcher", :light_gray
    end

    private def node_log(msg)
      @logger.puts msg, "NodeJS", :dark_gray
    end
  end
end

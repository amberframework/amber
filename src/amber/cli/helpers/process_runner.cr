require "./helpers"

module Sentry
  class ProcessRunner
    property processes = [] of Process
    property process_name : String
    property files = [] of String
    @logger : Amber::Environment::Logger
    FILE_TIMESTAMPS = {} of String => String

    def initialize(
      @process_name : String,
      @build_command : String,
      @run_command : String,
      @build_args : Array(String) = [] of String,
      @run_args : Array(String) = [] of String,
      files = [] of String,
      @logger = Amber::CLI.logger
    )
      @files = files
      @npm_process = false
      @app_running = false
    end

    def run
      loop do
        scan_files
        check_processes
        sleep 1
      end
    end

    # Compiles and starts the application
    def start_app
      time = Time.monotonic
      build_result = build_app_process
      return unless build_result.is_a? Process::Status

      if build_result.success?
        log "Compiled in #{(Time.monotonic - time)}"
        stop_all_processes if @app_running
        create_all_processes
        @app_running = true
      elsif !@app_running
        log "Compile time errors detected. Shutting down..."
        exit 1
      end
    end

    private def scan_files
      file_counter = 0
      Dir.glob(files) do |file|
        timestamp = get_timestamp(file)
        if FILE_TIMESTAMPS[file]? != timestamp
          log "File changed: #{file.colorize(:light_gray)}" if @app_running
          FILE_TIMESTAMPS[file] = timestamp
          file_counter += 1
        end
      end
      if file_counter > 0
        log "#{file_counter} file(s) changed. Recompiling..." if @app_running
        start_app
      end
    end

    private def check_processes
      @processes.reject!(&.terminated?)
      if @processes.empty?
        log "All processed died. Trying to start..."
        if (process = create_watch_process).is_a? Process
          @processes << process
        end
      end
    end

    private def stop_all_processes
      log "Terminating app #{project_name}..."
      @processes.each do |process|
        process.kill unless process.terminated?
      end
      processes.clear
    end

    private def create_all_processes
      process = create_watch_process
      @processes << process if process.is_a? Process
      unless @npm_process
        create_npm_process
        @npm_process = true
      end
    end

    private def build_app_process
      log "Building project #{project_name}..."
      Amber::CLI::Helpers.run(@build_command)
    end

    private def create_watch_process
      log "Starting #{project_name}..."
      Amber::CLI::Helpers.run(@run_command, wait: false, shell: false)
    end

    private def create_npm_process
      node_log "Installing dependencies..."
      Amber::CLI::Helpers.run("npm install --loglevel=error && npm run watch", wait: false)
      node_log "Watching public directory"
    end

    private def get_timestamp(file : String)
      File.info(file).modification_time.to_s("%Y%m%d%H%M%S")
    end

    private def project_name
      process_name.capitalize.colorize(:white)
    end

    private def log(msg)
      @logger.info msg, "Watcher", :light_gray
    end

    private def node_log(msg)
      @logger.info msg, "NodeJS", :dark_gray
    end
  end
end

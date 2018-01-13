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
        sleep 1
      end
    end

    # Compiles and starts the application
    def start_app
      build_result = build_app_process
      if build_result && build_result.success?
        stop_all_processes
        create_all_processes
        @app_running = true
      elsif !@app_running
        log "Compile time errors detected. Shutting down..."
        exit 1
      else
        log "Unknown error occurred, Shutting down..."
        exit 1
      end
    end

    private def scan_files
      file_counter = 0
      Dir.glob(files) do |file|
        timestamp = get_timestamp(file)
        if FILE_TIMESTAMPS[file]? != timestamp
          if @app_running
            log "File changed: #{file.colorize(:light_gray)}"
          end
          FILE_TIMESTAMPS[file] = timestamp
          file_counter += 1
        end
      end
      if file_counter > 0
        log "Watching #{file_counter} files (server reload)..."
        start_app
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
      @processes << create_watch_process
      unless @npm_process
        create_npm_process
        @npm_process = true
      end
    end

    private def build_app_process
      log "Building project #{project_name}..."
      Process.run(@build_command, shell: true, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    end

    private def create_watch_process
      log "Starting #{project_name}..."
      Process.new(@run_command, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    end

    private def create_npm_process
      node_log "Installing dependencies..."
      Process.new("npm install --loglevel=error && npm run watch", shell: true, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
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

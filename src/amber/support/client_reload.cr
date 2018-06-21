require "../cli/helpers/file_watcher"
require "../cli/helpers/helpers"
require "../cli/config"

module Amber::Support
  # Used by `Amber::Pipe::Reload`
  #
  # Allow clients browser reloading using WebSockets and file watchers.
  struct ClientReload
    SESSIONS  = [] of HTTP::WebSocket
    PROCESSES = [] of Process
    AMBER_YML = ".amber.yml"

    @file_watcher = FileWatcher.new
    @app_running = false

    def initialize
      at_exit do
        kill_client_processes
      end
    end

    def config
      if File.exists?(AMBER_YML)
        CLI::Config.from_yaml(File.read(AMBER_YML))
      else
        CLI::Config.new
      end
    end

    def run
      if watch_config = config.watch
        run_watcher(watch_config)
      else
        warn "Can't find watch settings, do you want to add default watch settings? (y/n)"
        if gets.to_s.lowercase == "y"
          generate_config
        end
        exit 1
      end
    rescue ex : KeyError
      error "Error in watch configuration. #{ex.message}"
      exit 1
    end

    private def generate_config
      File.write(AMBER_YML, config.to_yaml)
    end

    private def run_watcher(watch_config)
      entries = watch_config["client"]
      commands = entries["commands"]
      files = entries["files"]
      if files.empty?
        run_commands(commands)
      else
        spawn watcher(files, commands)
      end
      create_reload_server
    rescue ex
      error "Error in watch configuration. #{ex.message}"
      exit 1
    end

    private def watcher(files, commands)
      loop do
        scan_files(files, commands)
        @app_running = true
        sleep 1
      end
    end

    private def create_reload_server
      Amber::WebSockets::Server::Handler.new "/client-reload" do |session|
        SESSIONS << session
        session.on_close do
          SESSIONS.delete session
        end
      end
    end

    def scan_files(files, commands)
      file_counter = 0
      @file_watcher.scan_files(files) do |file|
        if @app_running
          debug "File changed: #{file}"
        end
        file_counter += 1
        check_file(file)
      end
      if file_counter > 0
        debug "Watching #{file_counter} client files..."
        kill_client_processes
        run_commands(commands)
      end
    end

    private def check_file(file)
      case file
      when .ends_with? ".css"
        reload_clients(msg: "refreshcss")
      else
        reload_clients(msg: "reload")
      end
    end

    private def reload_clients(msg)
      SESSIONS.each do |session|
        session.@ws.send msg
      end
    end

    private def run_commands(commands)
      commands.each do |command|
        PROCESSES << CLI::Helpers.run(command)
      end
    end

    private def kill_client_processes
      PROCESSES.each do |process|
        process.kill unless process.terminated?
        PROCESSES.delete(process)
      end
    end

    private def debug(msg)
      Amber.logger.debug msg, "Watcher", :light_gray
    end

    private def error(msg)
      Amber.logger.error msg, "Watcher", :red
    end

    private def warn(msg)
      CLI.logger.warn msg, "Watcher", :yellow
    end
  end
end

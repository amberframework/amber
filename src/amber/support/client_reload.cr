module Amber::Support
  # Allow clients browser reloading using WebSockets and file watchers.
  struct ClientReload
    Log = ::Log.for(self)

    FILE_TIMESTAMPS = {} of String => String
    WEBSOCKET_PATH  = "client-reload"
    SESSIONS        = [] of HTTP::WebSocket

    def initialize
      create_reload_server
      @app_running = false
      spawn run
    end

    def run
      loop do
        scan_files
        @app_running = true
        sleep 1
      end
    end

    private def create_reload_server
      Amber::WebSockets::Server::Handler.new "/#{WEBSOCKET_PATH}" do |session|
        SESSIONS << session
        session.on_close do
          SESSIONS.delete session
        end
      end
    end

    private def reload_clients(msg)
      SESSIONS.each do |session|
        session.@ws.send msg
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

    private def get_timestamp(file : String)
      File.info(file).modification_time.to_s("%Y%m%d%H%M%S")
    end

    private def scan_files
      file_counter = 0
      Dir.glob(["public/**/*"]) do |file|
        timestamp = get_timestamp(file)
        if FILE_TIMESTAMPS[file]? != timestamp
          if @app_running
            log "File changed: ./#{file.colorize(:light_gray)}"
          end
          FILE_TIMESTAMPS[file] = timestamp
          file_counter += 1
          check_file(file)
        end
      end
      if file_counter > 0
        log "Watching #{file_counter} files (browser reload)..."
      end
    end

    def log(message)
      Log.info { message.colorize(:light_gray) }
    end
  end
end

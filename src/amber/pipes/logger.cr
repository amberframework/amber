module Amber
  module Pipe
    class Logger < Base
      # Reads `Amber.settings` only when the pipe is built, which happens in
      # `config/routes.cr` after the app's initializers have registered their
      # settings sections. A read while `require "amber"` runs would cache the
      # settings before those sections exist.
      def initialize(@filter : Array(String) = log_config.filter,
                     @skip : Array(String) = log_config.skip,
                     @colorize : Bool = log_config.colorize)
      end

      def call(context : HTTP::Server::Context)
        time = Time.utc
        call_next(context)
        status = context.response.status_code
        elapsed = elapsed_text(Time.utc - time)
        request(context, time, elapsed, status, :magenta)
        log_other(context.request.headers, "headers")
        log_other(context.request.cookies, "cookies", :light_blue)
        log_other(context.params, "params", :light_blue)
        log_other(context.session, "session", :light_yellow)
        context
      end

      private def request(context, time, elapsed, status, color = :magenta)
        msg = String.build do |str|
          str << "Status: #{http_status(status)} Method: #{method(context)}"
          str << " Pipeline: #{paint(context.valve, color)} Format: #{paint(context.format, color)}"
        end
        log "Started #{paint(time, color)}", "request", color
        log msg, "Request", color
        log "Requested Url: #{paint(context.requested_url, color)}", "request", color
        log "Time Elapsed: #{paint(elapsed, color)}", "request", color
      end

      private def log_other(other, name, color = :light_cyan)
        other.to_h.each do |key, val|
          next if @skip.includes? key
          if @filter.includes? key.to_s
            log "#{key}: #{paint("FILTERED", :white).mode(:underline)}", name, color
          else
            log "#{key}: #{paint(val, color)}", name, color
          end
        end
      end

      private def method(context)
        paint(context.request.method, :light_red).to_s
      end

      private def http_status(status)
        case status
        when 200..299 then paint(status, :green)
        when 300..399 then paint(status, :blue)
        when 400..499 then paint(status, :yellow)
        when 500..599 then paint(status, :red)
        else
          paint(status, :white)
        end
      end

      private def elapsed_text(elapsed)
        millis = elapsed.total_milliseconds
        return "#{millis.round(2)}ms" if millis >= 1
        "#{(millis * 1000).round(2)}µs"
      end

      private def log(msg, prog, color = :white)
        Log.for(paint(prog, color).to_s).debug { msg }
      end

      private def paint(value, color)
        Support::LogColor.paint(value, color, @colorize)
      end

      private def log_config
        Amber.settings.logging
      end
    end
  end
end

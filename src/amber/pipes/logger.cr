module Amber
  module Pipe
    class Logger < Base
      Colorize.enabled = Amber.settings.logging.colorize

      def initialize(@filter : Array(String) = log_config.filter,
                     @skip : Array(String) = log_config.skip)
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
          str << " Pipeline: #{context.valve.colorize(color)} Format: #{context.format.colorize(color)}"
        end
        log "Started #{time.colorize(color)}", "request", color
        log msg, "Request", color
        log "Requested Url: #{context.requested_url.colorize(color)}", "request", color
        log "Time Elapsed: #{elapsed.colorize(color)}", "request", color
      end

      private def log_other(other, name, color = :light_cyan)
        other.to_h.each do |key, val|
          next if @skip.includes? key
          if @filter.includes? key.to_s
            log "#{key}: #{"FILTERED".colorize(:white).mode(:underline)}", name, color
          else
            log "#{key}: #{val.colorize(color)}", name, color
          end
        end
      end

      private def method(context)
        context.request.method.colorize(:light_red).to_s
      end

      private def http_status(status)
        case status
        when 200..299 then status.colorize(:green)
        when 300..399 then status.colorize(:blue)
        when 400..499 then status.colorize(:yellow)
        when 500..599 then status.colorize(:red)
        else
          status.colorize(:white)
        end
      end

      private def elapsed_text(elapsed)
        millis = elapsed.total_milliseconds
        return "#{millis.round(2)}ms" if millis >= 1
        "#{(millis * 1000).round(2)}µs"
      end

      private def log(msg, prog, color = :white)
        Log.for(prog).debug { "#{prog.colorize(color)} | #{msg}" }
      end

      private def log_config
        Amber.settings.logging
      end
    end
  end
end

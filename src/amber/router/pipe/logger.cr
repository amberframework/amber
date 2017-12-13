require "colorize"

module Amber
  module Pipe
    class Logger < Base
      alias Params = Array(String)
      FILTERED      = %w(password confirm_password)
      FILTERED_TEXT = "FILTERED".colorize(:white).mode(:underline)

      def initialize(@filtered : Params = FILTERED, @reject : Params = Params.new)
      end

      def call(context : HTTP::Server::Context)
        time = Time.now
        call_next(context)
        status = context.response.status_code
        elapsed = elapsed_text(Time.now - time)
        request(context, time, elapsed, status, :magenta)
        log_other(context.request.headers, "Headers")
        log_other(context.params, "Params", :light_blue)
        log_other(context.session, "Session", :light_yellow)
        context
      end

      private def request(context, time, elapsed, status, color = :magenta)
        msg = String.build do |str|
          str << "Status: #{http_status(status)} Method: #{method(context)}"
          str << " Pipeline: #{context.valve.colorize(color)} Format: #{context.format.colorize(color)}"
        end
        log "Started #{time.colorize(color)}", "Request", color
        log msg, "Request", color
        log "Requested Url: #{context.requested_url.colorize(color)}", "Request", color
        log "Time Elapsed: #{elapsed.colorize(color)}", "Request", color
      end

      private def log_other(other, name, color = :light_cyan)
        other.to_h.each do |key, val|
          next if @reject.includes? key
          if @filtered.includes? key.to_s
            log "#{key}: #{FILTERED_TEXT}", name, color
          else
            log "#{key}: #{val.colorize(color)}", name, color
          end
        end
      end

      private def method(context)
        colorize(context.request.method, :light_red).to_s + " "
      end

      private def http_status(status)
        case status
        when 200
          text = colorize("200 ", :green)
        when 404
          text = colorize("404 ", :red)
        end
        "#{text}"
      end

      private def elapsed_text(elapsed)
        millis = elapsed.total_milliseconds
        return "#{millis.round(2)}ms" if millis >= 1
        "#{(millis * 1000).round(2)}µs"
      end

      private def colorize(text, color)
        text.colorize(color)
      end

      private def log(msg, prog, color = :white)
        Amber.logger.puts msg, prog, color
      end
    end
  end
end

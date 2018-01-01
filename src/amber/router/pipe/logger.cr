module Amber
  module Pipe
    class Logger < Base
      alias Params = Array(String?)
      Colorize.enabled = Amber.settings.logging.colorize
      FILTERED_TEXT = "FILTERED".colorize(:white).mode(:underline)

      def initialize(@filter : Params = log_config.filter,
                     @skip : Params = log_config.skip,
                     @context : Params = log_config.context)
      end

      def call(context : HTTP::Server::Context)
        time = Time.now
        call_next(context)
        status = context.response.status_code
        elapsed = elapsed_text(Time.now - time)
        request(context, time, elapsed, status, :magenta) if @context.includes? "request"
        log_other(context.request.headers, "Headers") if @context.includes? "headers"
        log_other(context.request.cookies, "Cookies", :light_blue) if @context.includes? "cookies"
        log_other(context.params, "Params", :light_blue) if @context.includes? "params"
        log_other(context.session, "Session", :light_yellow) if @context.includes? "session"
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
          next if @skip.includes? key
          if @filter.includes? key.to_s
            log "#{key}: #{FILTERED_TEXT}", name, color
          else
            log "#{key}: #{val.colorize(color)}", name, color
          end
        end
      end

      private def method(context)
        context.request.method.colorize(:light_red).to_s + " "
      end

      private def http_status(status)
        case status
        when 200
          text = "200 ".colorize(:green)
        when 404
          text = "404 ".colorize(:red)
        end
        "#{text}"
      end

      private def elapsed_text(elapsed)
        millis = elapsed.total_milliseconds
        return "#{millis.round(2)}ms" if millis >= 1
        "#{(millis * 1000).round(2)}µs"
      end

      private def log(msg, prog, color = :white)
        Amber.logger.puts msg, prog, color
      end

      private def log_config
        Amber.settings.logging
      end
    end
  end
end

require "colorize"

module Amber
  module Pipe
    class Logger < Base
      property log : ::Logger

      def self.instance
        @@instance ||= new
      end

      def initialize
        @log = Amber::Server.instance.log
      end

      def call(context : HTTP::Server::Context)
        time = Time.now
        call_next(context)
        status = context.response.status_code
        elapsed = elapsed_text(Time.now - time)
        @log.info "#{http_status(status)} | #{method(context)} #{path(context)} | #{elapsed}"
        @log.info "Params: #{context.params.to_s.colorize(:yellow)}"
        context
      end

      def method(context)
        context.request.method.colorize(:light_red).to_s + " "
      end

      def path(context)
        "\"" + context.request.path.to_s.colorize(:yellow).to_s + "\" "
      end

      def http_status(status)
        case status
        when 200
          text = "200 ".colorize(:green).to_s
        when 404
          text = "404 ".colorize(:red).to_s
        end
        "#{text}"
      end

      private def elapsed_text(elapsed)
        millis = elapsed.total_milliseconds
        return "#{millis.round(2)}ms" if millis >= 1
        "#{(millis * 1000).round(2)}µs"
      end
    end
  end
end

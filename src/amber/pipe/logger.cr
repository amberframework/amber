require "colorize"
require "logger"

module Amber
  module Pipe
    class Logger < Base
      def self.instance
        @@instance ||= new
      end

      def call(context : HTTP::Server::Context)
        time = Time.now
        call_next(context)
        status_code = context.response.status_code
        method = context.request.method
        resource = context.request.resource
        elapsed = elapsed_text(Time.now - time)
        puts "#{status_code} | #{method} #{resource} | #{elapsed}"
        context
      end

      private def elapsed_text(elapsed)
        millis = elapsed.total_milliseconds
        return "#{millis.round(2)}ms" if millis >= 1
        "#{(millis * 1000).round(2)}µs"
      end
    end
  end
end

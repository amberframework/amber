require "colorize"
require "logger"

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
        elapsed = elapsed_text(Time.now - time)

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

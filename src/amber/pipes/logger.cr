module Amber
  module Pipe
    class Logger < Base
      # The log sources this pipe writes to, in the order it writes them.
      SOURCE_NAMES = {"request", "Request", "headers", "cookies", "params", "session"}

      # The color each source name is painted with, by position in `SOURCE_NAMES`.
      SOURCE_COLORS = {:magenta, :magenta, :light_cyan, :light_blue, :light_blue, :light_yellow}

      # The `::Log` instances behind one spelling of the source names: plain, or
      # painted when colored output is on. `::Log` instances are kept up to date
      # by `Log.setup` in place, so holding them keeps their levels current.
      private record Sources,
        request : ::Log,
        request_summary : ::Log,
        headers : ::Log,
        cookies : ::Log,
        params : ::Log,
        session : ::Log do
        # Returns `true` when at least one source would write a debug line.
        def writes_any_line? : Bool
          {request, request_summary, headers, cookies, params, session}.any? do |log|
            Logger.writes_debug?(log)
          end
        end
      end

      @plain_sources : Sources
      @painted_sources : Sources

      # Reads `Amber.settings` only when the pipe is built, which happens in
      # `config/routes.cr` after the app's initializers have registered their
      # settings sections. A read while `require "amber"` runs would cache the
      # settings before those sections exist.
      def initialize(@filter : Array(String) = log_config.filter,
                     @skip : Array(String) = log_config.skip,
                     @colorize : Bool = log_config.colorize)
        @plain_sources = build_sources(painted: false)
        @painted_sources = build_sources(painted: true)
      end

      # Returns `true` when *log* would write a debug line.
      #
      # ```
      # Amber::Pipe::Logger.writes_debug?(::Log.for("request"))
      # ```
      def self.writes_debug?(log : ::Log) : Bool
        !log.backend.nil? && log.level <= ::Log::Severity::Debug
      end

      # Logs the request at debug level after the rest of the pipeline runs.
      #
      # When no source would write a debug line (Amber's default `info` level),
      # it passes the request on and allocates nothing: it does not read the
      # clock, parse params, or build the session.
      def call(context : HTTP::Server::Context)
        sources = current_sources
        unless sources.writes_any_line?
          call_next(context)
          return context
        end

        time = Time.utc
        call_next(context)
        elapsed = Time.utc - time
        log_request(sources, context, time, elapsed)
        log_headers(sources.headers, context.request.headers)
        if Logger.writes_debug?(sources.cookies)
          log_other(sources.cookies, Amber::Router::Cookies::Store.from_headers(context.request.headers), :light_blue)
        end
        log_other(sources.params, context.params, :light_blue) if Logger.writes_debug?(sources.params)
        log_other(sources.session, context.session, :light_yellow) if Logger.writes_debug?(sources.session)
        context
      end

      # Colored source names are only written when this pipe colors its lines
      # and the app has left `Colorize` on, the same rule `LogColor` follows.
      private def current_sources : Sources
        @colorize && Colorize.enabled? ? @painted_sources : @plain_sources
      end

      private def build_sources(painted : Bool) : Sources
        logs = SOURCE_NAMES.map_with_index do |name, index|
          source = painted ? Support::LogColor.paint(name, SOURCE_COLORS[index], true).to_s : name
          ::Log.for(source)
        end
        Sources.new(*logs)
      end

      private def log_request(sources, context, time, elapsed) : Nil
        color = :magenta
        sources.request.debug { "Started #{paint(time, color)}" }
        sources.request_summary.debug do
          String.build do |line|
            line << "Status: " << http_status(context.response.status_code)
            line << " Method: " << paint(context.request.method, :light_red)
            line << " Pipeline: " << paint(context.valve, color)
            line << " Format: " << paint(context.format, color)
          end
        end
        sources.request.debug { "Requested Url: #{paint(context.requested_url, color)}" }
        sources.request.debug { "Time Elapsed: #{paint(elapsed_text(elapsed), color)}" }
      end

      # Walks the headers in place rather than copying them into a hash first.
      private def log_headers(log, headers : HTTP::Headers) : Nil
        return unless Logger.writes_debug?(log)
        headers.each do |key, values|
          log_value(log, key, values, :light_cyan)
        end
      end

      private def log_other(log, other, color) : Nil
        other.to_h.each do |key, value|
          log_value(log, key, value, color)
        end
      end

      private def log_value(log, key, value, color) : Nil
        return if @skip.includes? key
        if @filter.includes? key.to_s
          log.debug { "#{key}: #{paint("FILTERED", :white).mode(:underline)}" }
        else
          log.debug { "#{key}: #{paint(value, color)}" }
        end
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

      private def paint(value, color)
        Support::LogColor.paint(value, color, @colorize)
      end

      private def log_config
        Amber.settings.logging
      end
    end
  end
end

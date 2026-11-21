require "log/spec"
require "../../spec_helper"

module Amber::Pipe
  private def self.requested_url_line(pipe : Logger) : String
    pipe.next = ->(_context : HTTP::Server::Context) { }
    context = create_context(HTTP::Request.new("GET", "/logger_spec"))
    line = ""
    Log.capture("*", :debug) do |logs|
      pipe.call(context)
      logs.check("the requested URL line") { |entry| entry.message.starts_with?("Requested Url: ") }
      line = logs.entry.message
    end
    line
  end

  private def self.with_global_colorize(enabled : Bool, &)
    previous = Colorize.enabled?
    begin
      Colorize.enabled = enabled
      yield
    ensure
      Colorize.enabled = previous
    end
  end

  describe Logger do
    before_all do
      Amber::Server.router.draw :web do
        get "/logger_spec", HelloController, :world
      end
    end

    describe "#initialize" do
      it "leaves the process-wide Colorize flag as the app set it" do
        with_global_colorize(false) do
          Logger.new(colorize: true)

          Colorize.enabled?.should be_false
        end
      end

      it "takes its colorize default from the logging settings" do
        with_global_colorize(true) do
          line = requested_url_line(Logger.new)

          line.includes?("\e[").should eq Amber.settings.logging.colorize
        end
      end
    end

    describe "#call" do
      it "allocates nothing when the level filters every line out" do
        pipe = Logger.new(colorize: false)
        pipe.next = ->(_context : HTTP::Server::Context) { }
        context = create_context(HTTP::Request.new("GET", "/logger_spec?page=2", HTTP::Headers{"Cookie" => "a=b"}))
        Log.capture("*", :info) do |logs|
          pipe.call(context)
          before = GC.stats.total_bytes
          100.times { pipe.call(context) }
          (GC.stats.total_bytes - before).should eq 0
          logs.empty
        end
      end

      it "writes the request, header, cookie and param lines at debug level" do
        pipe = Logger.new(filter: ["password"], skip: ["Host"], colorize: false)
        pipe.next = ->(_context : HTTP::Server::Context) { }
        request = HTTP::Request.new("GET", "/logger_spec?page=2&password=secret",
          HTTP::Headers{"Host" => "example.com", "Accept" => "text/html", "Cookie" => "flavor=oat"})
        Log.capture("*", :debug) do |logs|
          pipe.call(create_context(request))
          logs.check(:debug, /^Started /)
          logs.check(:debug, /^Status: 200 Method: GET Pipeline: /)
          logs.check(:debug, "Requested Url: /logger_spec?page=2&password=secret")
          logs.check(:debug, /^Time Elapsed: /)
          logs.check(:debug, %(Accept: ["text/html"]))
          logs.check(:debug, /^flavor: /)
          logs.check(:debug, "page: 2")
          logs.check(:debug, "password: FILTERED")
        end
      end

      it "logs plain text when colorize is false" do
        with_global_colorize(true) do
          requested_url_line(Logger.new(colorize: false)).should eq "Requested Url: /logger_spec"
        end
      end

      it "logs colored text when colorize is true" do
        with_global_colorize(true) do
          requested_url_line(Logger.new(colorize: true)).should eq "Requested Url: \e[35m/logger_spec\e[39m"
        end
      end
    end
  end
end

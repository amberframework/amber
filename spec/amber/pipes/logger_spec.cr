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
    Colorize.enabled = enabled
    yield
  ensure
    Colorize.enabled = previous unless previous.nil?
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

require "../../spec_helper"

module Amber::Pipe
  describe Logger do
    describe "#initialize" do
      it "applies the logging.colorize setting when the pipe is built" do
        previous_colorize = Colorize.enabled?
        begin
          Colorize.enabled = !Amber.settings.logging.colorize

          Logger.new

          Colorize.enabled?.should eq Amber.settings.logging.colorize
        ensure
          Colorize.enabled = previous_colorize
        end
      end
    end
  end
end

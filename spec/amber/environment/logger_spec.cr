require "../../spec_helper"

module Amber::Environment
  describe Logger do
    describe "#log" do
      it "logs messages with progname" do
        IO.pipe do |r, w|
          Colorize.enabled = false

          logger = Logger.new(w)
          logger.progname = "Amber"
          logger.debug "debug:skip"
          logger.info "info:show"

          logger.level = Log::Severity::Debug
          logger.debug "debug:show"

          logger.level = Log::Severity::Warning
          logger.debug "debug:skip:again"
          logger.info "info:skip"
          logger.error "error:show"

          r.gets.should match(/Amber | info:show/)
          r.gets.should match(/Amber | debug:show/)
          r.gets.should match(/Amber | error:show/)
        end
      end
    end
    describe "#color" do
      it "logs messages with passed color attribute" do
        IO.pipe do |r, w|
          logger = Logger.new(w)
          Colorize.enabled = true
          logger.info "Test", "Amber", :blue
          r.gets.should match(/\[34mAmber/)
        end
      end
      it "logs messages with default color attribute" do
        IO.pipe do |r, w|
          logger = Logger.new(w)
          logger.progname = "Amber"
          Colorize.enabled = true
          logger.info "Test"
          r.gets.should match(/\[96mAmber/)
        end
      end
      it "logs messages when #color is used" do
        IO.pipe do |r, w|
          logger = Logger.new(w)
          logger.progname = "Amber"
          logger.color = :green
          Colorize.enabled = true
          logger.info "Test"
          r.gets.should match(/\[32mAmber/)
        end
      end
    end
  end
end

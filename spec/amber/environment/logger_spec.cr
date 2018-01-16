require "../../spec_helper"

module Amber::Environment
  describe Logger do
    describe "#log" do
      it "logs messages with progname" do
        IO.pipe do |r, w|
          logger = Logger.new(w)
          logger.progname = "Amber"
          logger.debug "debug:skip"
          logger.info "info:show"

          logger.level = Logger::DEBUG
          logger.debug "debug:show"

          logger.level = Logger::WARN
          logger.debug "debug:skip:again"
          logger.info "info:skip"
          logger.error "error:show"

          r.gets.should match(/Amber\t| info:show/)
          r.gets.should match(/Amber\t| debug:show/)
          r.gets.should match(/Amber\t| error:show/)
        end
      end
    end
  end
end

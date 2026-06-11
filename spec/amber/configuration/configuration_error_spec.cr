require "../../spec_helper"

module Amber::Exceptions
  describe ConfigurationError do
    describe "single error" do
      it "stores the error message" do
        error = ConfigurationError.new("server.port is invalid")
        error.message.should eq "server.port is invalid"
        error.list_of_errors.should eq ["server.port is invalid"]
      end
    end

    describe "multiple errors" do
      it "stores all error messages" do
        errors = [
          "server.port must be between 1 and 65535",
          "logging.severity must be a valid level",
          "jobs.workers must be at least 1",
        ]
        error = ConfigurationError.new(errors)
        error.list_of_errors.size.should eq 3
        error.message.not_nil!.should contain("server.port")
        error.message.not_nil!.should contain("logging.severity")
        error.message.not_nil!.should contain("jobs.workers")
      end

      it "formats the error message with bullet points" do
        errors = ["error one", "error two"]
        error = ConfigurationError.new(errors)
        error.message.not_nil!.should contain("  - error one")
        error.message.not_nil!.should contain("  - error two")
      end
    end
  end
end

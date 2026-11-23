require "../../spec_helper"

module Amber::Environment
  describe Logging do
    describe "#apply_severity_to_log" do
      it "sets every source to the severity the environment file names" do
        builder = ::Log::Builder.new
        backend = ::Log::MemoryBackend.new
        logging = Logging.new({"severity" => "error"} of String => String | Bool | Array(String))

        logging.apply_severity_to_log(backend, builder)

        server_log = builder.for("amber.server")
        server_log.level.should eq(::Log::Severity::Error)
        builder.for("request").level.should eq(::Log::Severity::Error)
        server_log.info { "Server started" }
        server_log.error { "Server stopped" }
        backend.entries.map(&.message).should eq(["Server stopped"])
      end

      it "lets the request logger write its debug lines at debug" do
        builder = ::Log::Builder.new
        logging = Logging.new({"severity" => "debug"} of String => String | Bool | Array(String))

        logging.apply_severity_to_log(::Log::MemoryBackend.new, builder)

        Amber::Pipe::Logger.writes_debug?(builder.for("request")).should be_true
      end

      it "replaces the level bound before it, such as the one LOG_LEVEL set" do
        builder = ::Log::Builder.new
        ::Log.setup(::Log::Severity::Info, ::Log::MemoryBackend.new, builder: builder)
        logging = Logging.new({"severity" => "warn"} of String => String | Bool | Array(String))

        logging.apply_severity_to_log(::Log::MemoryBackend.new, builder)

        builder.for("boot").level.should eq(::Log::Severity::Warn)
      end

      it "writes nothing at none" do
        builder = ::Log::Builder.new
        backend = ::Log::MemoryBackend.new
        logging = Logging.new({"severity" => "none"} of String => String | Bool | Array(String))

        logging.apply_severity_to_log(backend, builder)

        builder.for("amber.server").fatal { "unreachable" }
        backend.entries.should be_empty
      end
    end

    it "takes its severity from AMBER_LOGGING_SEVERITY over the environment file" do
      Dir.cd CURRENT_DIR
      previous_value = ENV["AMBER_LOGGING_SEVERITY"]?
      ENV["AMBER_LOGGING_SEVERITY"] = "error"
      begin
        settings = Loader.new("v2_test", "./spec/support/config/").settings
        settings.logging.severity.should eq(::Log::Severity::Error)
      ensure
        if previous_value
          ENV["AMBER_LOGGING_SEVERITY"] = previous_value
        else
          ENV.delete("AMBER_LOGGING_SEVERITY")
        end
      end
    end
  end
end

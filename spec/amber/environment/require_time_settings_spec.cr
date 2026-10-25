require "file_utils"
require "../../spec_helper"

# Compiles spec/fixtures/require_time_settings/probe_app.cr as its own program
# and runs it from an empty directory. The suite's spec_helper loads settings
# before `require "amber"`, so only a separate program can show whether
# requiring Amber reads `Amber.settings` or `Amber.env`.
module RequireTimeSettingsProbe
  FIXTURE_DIRECTORY = File.expand_path("../../fixtures/require_time_settings", __DIR__)

  record Outcome, status : Process::Status, output : String do
    def value_for(key : String) : String?
      output.each_line do |line|
        line_key, separator, value = line.partition('=')
        return value if separator == "=" && line_key == key
      end
    end
  end

  @@outcome : Outcome?

  def self.outcome : Outcome
    @@outcome ||= build_and_run
  end

  private def self.compiler : String
    ENV["CRYSTAL"]? || Process.find_executable("crystal-alpha") || "crystal"
  end

  private def self.build_and_run : Outcome
    work_directory = File.tempname("amber-require-time-settings")
    Dir.mkdir_p(work_directory)
    binary = File.join(work_directory, "probe_app")
    source = File.join(FIXTURE_DIRECTORY, "probe_app.cr")

    build_output = IO::Memory.new
    build = Process.run(compiler, ["build", source, "-o", binary],
      output: build_output, error: build_output)
    raise "#{source} did not compile:\n#{build_output}" unless build.success?

    run_output = IO::Memory.new
    status = Process.run(binary, [File.join(FIXTURE_DIRECTORY, "config", "environments")],
      env: {"AMBER_ENV" => nil}, chdir: work_directory,
      output: run_output, error: run_output)
    Outcome.new(status, run_output.to_s)
  ensure
    FileUtils.rm_rf(work_directory) if work_directory
  end
end

describe "settings loading after require \"amber\"" do
  it "loads a custom section registered after require from its YAML value" do
    outcome = RequireTimeSettingsProbe.outcome

    outcome.status.success?.should be_true, outcome.output
    outcome.value_for("probe.label").should eq "from-yaml"
  end

  it "reads neither Amber.settings nor Amber.env while Amber is being required" do
    outcome = RequireTimeSettingsProbe.outcome

    outcome.status.success?.should be_true, outcome.output
    outcome.value_for("name").should eq "lazy_probe_app"
    outcome.value_for("env").should eq "lazy_probe"
  end
end

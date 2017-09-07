require "../../../spec_helper"

module Amber::CLI
  begin
    describe MainCommand::Encrypt do
      context "application structure" do
        it "creates amber directory structure" do
          MainCommand.run ["new", TESTING_APP]
          Dir.exists?(TESTING_APP).should be_true
          Dir.cd(TESTING_APP)
          MainCommand.run ["encrypt", "test"]
          File.exists?("config/environments/.test.enc").should be_true
          File.read(".amber_secret_key").size.should eq 44
          Amber::CLI::Spec.cleanup
        end
      end
    end
  ensure
    Amber::CLI::Spec.cleanup
  end
end

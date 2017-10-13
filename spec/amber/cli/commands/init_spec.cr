require "../../../spec_helper"

module Amber::CLI
  begin
    describe MainCommand::New do
      context "application structure" do
        it "creates amber directory structure" do
          MainCommand.run ["new", TESTING_APP]

          Dir.exists?(TESTING_APP).should be_true
          Amber::CLI::Spec.dirs(TESTING_APP).sort.should eq Amber::CLI::Spec.dirs(APP_TPL_PATH).sort
          Amber::CLI::Spec.db_yml["pg"].should_not be_nil
          shard_yaml = Amber::CLI::Spec.shard_yml
          shard_yaml["dependencies"]["pg"].should_not be_nil
          shard_yaml["dependencies"]["amber"]["version"].should eq Amber::VERSION
          Amber::CLI::Spec.amber_yml["language"].should eq "slang"
          File.read("#{TESTING_APP}/.amber_secret_key").size.should eq 44
          Amber::CLI::Spec.cleanup
        end
      end

      context "database" do
        it "create app with mysql settings" do
          MainCommand.run ["new", TESTING_APP, "-d", "mysql", "-t", "ecr"]

          Amber::CLI::Spec.db_yml["mysql"].should_not be_nil
          Amber::CLI::Spec.shard_yml["dependencies"]["mysql"].should_not be_nil
          Amber::CLI::Spec.amber_yml["language"].should eq "ecr"
          Amber::CLI::Spec.cleanup
        end

        it "creates app with sqlite settings" do
          MainCommand.run ["new", TESTING_APP, "-d", "sqlite"]

          Amber::CLI::Spec.db_yml["sqlite"].should_not be_nil
          Amber::CLI::Spec.shard_yml["dependencies"]["sqlite3"].should_not be_nil
          Amber::CLI::Spec.cleanup
        end
      end
    end
  ensure
    Amber::CLI::Spec.cleanup
  end
end

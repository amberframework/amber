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
        context "postgres" do
          MainCommand.run ["new", TESTING_APP]
          it "creates app with correct settings" do
            Amber::CLI::Spec.shard_yml["dependencies"]["pg"].should_not be_nil
            Amber::CLI::Spec.db_yml["pg"].should_not be_nil
            db_url = Amber::CLI::Spec.db_yml["pg"]["database"].as_s
            db_url.should_not be_nil

            db_name = Amber::CLI::Spec.db_name(db_url)
            db_name.should_not eq ""
            db_name.should_not contain "-"
          end

          it "creates app with correct environment database urls" do
            dev_db_url = Amber::CLI::Spec.development_yml["secrets"]["database"].as_s
            dev_db_url.should_not eq ""
            dev_db_url.should contain "development"
            test_db_url = Amber::CLI::Spec.test_yml["secrets"]["database"].as_s
            test_db_url.should_not eq ""
            test_db_url.should contain "test"

            [dev_db_url, test_db_url].each do |db_url|
              db_name = Amber::CLI::Spec.db_name(db_url)
              db_name.should_not eq ""
              db_name.should_not contain "-"
            end
          end

          it "creates app with correct docker-compose database urls and names" do
            db_env_db_name = Amber::CLI::Spec.docker_compose_yml["services"]["db"]["environment"]["POSTGRES_DB"].as_s
            app_env_db_url = Amber::CLI::Spec.docker_compose_yml["services"]["app"]["environment"]["DATABASE_URL"].as_s
            app_env_db_name = Amber::CLI::Spec.db_name(app_env_db_url)
            migrate_env_db_url = Amber::CLI::Spec.docker_compose_yml["services"]["migrate"]["environment"]["DATABASE_URL"].as_s
            migrate_env_db_name = Amber::CLI::Spec.db_name(migrate_env_db_url)

            [db_env_db_name, app_env_db_name, migrate_env_db_name].each do |db_name|
              db_name.should_not eq ""
              db_name.should contain "development"
              db_name.should_not contain "-"
            end
          end
          Amber::CLI::Spec.cleanup
        end

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

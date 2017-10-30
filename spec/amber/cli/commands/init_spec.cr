require "../../../spec_helper"
require "../../../support/helpers/cli_helper"

include CLIHelper

module Amber::CLI
  begin
    describe MainCommand::New do
      context "application structure" do
        it "creates amber directory structure" do
          scaffold_app(TESTING_APP)
          assert_app_directory_structure?(TESTING_APP, APP_TEMPLATE_PATH)
          cleanup
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
          MainCommand.run ["new", TESTING_APP, "-d", "mysql"]
          assert_correct_db_settings?("mysql")
          cleanup
        end

        it "creates app with postgres settings" do
          MainCommand.run ["new", TESTING_APP, "-d", "pg"]
          assert_correct_db_settings?("pg")
          cleanup
        end
      end

      context "template" do
        it "sets ECR templates" do
          MainCommand.run ["new", TESTING_APP, "-t", "ecr"]
          assert_correct_template_settings?("ecr")
          cleanup
        end

        it "it defaults to Slang templates" do
          MainCommand.run ["new", TESTING_APP]
          assert_correct_template_settings?("slang")
          cleanup
        end
      end
    end
  ensure
    cleanup
  end
end

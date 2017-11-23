require "../../../spec_helper"
require "../../../support/helpers/cli_helper"
require "../../../support/fixtures/cli_fixtures"

include CLIHelper
include CLIFixtures

module Amber::CLI
  describe "database" do
    describe "sqlite" do
      env = ENV["AMBER_ENV"]
      cleanup
      scaffold_app(TESTING_APP, "-d", "sqlite")

      context env do
        env_yml = environment_yml(env, path: CLIHelper::BASE_ENV_PATH)
        db_filename = env_yml["database_url"].to_s.gsub("sqlite3:", "")

        it "has connection settings in config/environments/env.yml" do
          env_yml["database_url"].should eq expected_db_url("sqlite3", env)
        end

        it "does not create the database when `db create`" do
          MainCommand.run ["db", "create"]
          File.exists?(db_filename).should be_false
        end

        it "does create the database when `db migrate`" do
          MainCommand.run ["generate", "model", "Post"]
          MainCommand.run ["db", "migrate"]
          p db_filename
          File.exists?(db_filename).should be_true
          File.stat(db_filename).size.should_not eq 0
        end

        it "deletes the database when `db drop`" do
          MainCommand.run ["db", "drop"]
          File.exists?(db_filename).should be_false
        end
      end
    end

    describe "postgres" do
      cleanup
      scaffold_app(TESTING_APP, "-d", "pg")
      env = ENV["AMBER_ENV"]

      context "when #{env} environment" do
        it "has #{env} environment connection settings" do
          environment_yml(env, path: CLIHelper::BASE_ENV_PATH)["database_url"].should eq expected_db_url("pg", env)
        end
      end
    end
  end
end

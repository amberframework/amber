require "../../../spec_helper"
require "../../../support/helpers/cli_helper"
require "../../../support/fixtures/cli_fixtures"

include CLIHelper
include CLIFixtures

module Amber::CLI
  describe "database" do
    describe "sqlite" do
      it "has connection settings in config/environments/env.yml" do
        db_url = ENV["DATABASE_URL"]?

        if ENV["DATABASE_URL"]?
          ENV.delete("DATABASE_URL")
        end
        env_yml = prepare_test_app
        env_yml["database_url"].should eq expected_db_url("sqlite3", env)
        cleanup

        unless ENV["DATABASE_URL"]?
          ENV["DATABASE_URL"] = db_url
        end
      end

      it "creates and deletes the database when db migrate and drop" do
        db_url = ENV["DATABASE_URL"]?

        if ENV["DATABASE_URL"]?
          ENV.delete("DATABASE_URL")
        end

        env_yml = prepare_test_app
        CLI.settings.database_url = env_yml["database_url"].to_s

        MainCommand.run ["generate", "model", "-y", "Post"]
        MainCommand.run ["db", "migrate"]

        db_filename = CLI.settings.database_url.to_s.gsub("sqlite3:", "")
        File.exists?(db_filename).should be_true
        File.info(db_filename).size.should_not eq 0

        MainCommand.run ["db", "drop"]

        db_filename = CLI.settings.database_url.gsub("sqlite3:", "")
        File.exists?(db_filename).should be_false
        cleanup

        unless ENV["DATABASE_URL"]?
          ENV["DATABASE_URL"] = db_url
        end
      end
    end

    describe "postgres" do
      it "has test connection settings" do
        db_url = ENV["DATABASE_URL"]?

        if ENV["DATABASE_URL"]?
          ENV.delete("DATABASE_URL")
        end

        scaffold_app("#{TESTING_APP}", "-d", "pg")
        env_yml = environment_yml("test", "#{Dir.current}/config/environments/")
        env_yml["database_url"].should eq expected_db_url("pg", env)
        cleanup

        unless ENV["DATABASE_URL"]?
          ENV["DATABASE_URL"] = db_url
        end
      end
    end
  end
end

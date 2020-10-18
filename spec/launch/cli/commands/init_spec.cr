require "../../../spec_helper"
require "../../../support/helpers/cli_helper"

include CLIHelper

module Launch::CLI
  def self.set_dir
    Dir.cd CURRENT_DIR
  end

  describe Launch::CLI::MainCommand::New do
    Spec.after_each do
      cleanup
    end

    it "launch new #{TESTING_APP}" do
      ENV["LAUNCH_ENV"] = "test"

      scaffold_app(TESTING_APP)
      camel_case = "PostComment"
      snake_case = "post_comment"
      class_definition_prefix = "class #{camel_case}"
      spec_definition_prefix = "describe #{camel_case}"

      # "generates launch directory structure" do
      dirs("../." + TESTING_APP).sort.should eq dirs(APP_TEMPLATE_PATH).sort
      # "follows naming conventions for all files and class names" do
      [camel_case, snake_case].each do |arg|
        MainCommand.run ["generate", "model", "-y", arg]
        filename = snake_case
        jennifer_table_name = "#{camel_case} < ApplicationModel"
        src_filepath = "./src/models/#{filename}.cr"
        spec_filepath = "./spec/models/#{filename}_spec.cr"
        File.exists?(src_filepath).should be_true
        File.exists?(spec_filepath).should be_true
        File.read(src_filepath).should contain class_definition_prefix
        File.read(src_filepath).should contain jennifer_table_name
        File.read(spec_filepath).should contain spec_definition_prefix
        File.delete(src_filepath)
        File.delete(spec_filepath)
      end
      cleanup
    end

    it "launch new #{TESTING_APP} --minimal" do
      ENV["LAUNCH_ENV"] = "test"

      scaffold_app(TESTING_APP, "--minimal")
      camel_case = "PostComment"
      snake_case = "post_comment"
      class_definition_prefix = "class #{camel_case}"
      spec_definition_prefix = "describe #{camel_case}"

      # "generates launch directory structure" do
      minimal_folders = dirs(APP_TEMPLATE_PATH) - ["src/assets/javascripts", "src/assets/stylesheets", "config/webpack",
                                                   "public/js", "src/views/home"]
      dirs("../." + TESTING_APP).sort.should eq minimal_folders.sort
      # "follows naming conventions for all files and class names" do
      [camel_case, snake_case].each do |arg|
        MainCommand.run ["generate", "model", "-y", arg]
        filename = snake_case
        jennifer_timestamps = "with_timestamps"
        src_filepath = "./src/models/#{filename}.cr"
        spec_filepath = "./spec/models/#{filename}_spec.cr"
        File.exists?(src_filepath).should be_true
        File.exists?(spec_filepath).should be_true
        File.read(src_filepath).should contain class_definition_prefix
        File.read(src_filepath).should contain jennifer_timestamps
        File.read(spec_filepath).should contain spec_definition_prefix
        File.delete(src_filepath)
        File.delete(spec_filepath)
      end
      cleanup
    end

    # This test fails because:
    # [04:03:28 Generate   | (INFO) Rendering App test_app in ./test_app from damianham/default
    # 04:03:29 Generate   | (ERROR) Could not find the recipe damianham/default : 404 Not Found
    # 04:03:29 Generate   | (INFO) Installing Dependencies
    # Missing shard.yml. Please run 'shards init'
    # Environment file not found for ./config/environments/production

    # context "-r recipe (damianham/default)" do
    #   it "generates launch directory structure" do
    #     puts Dir.current
    #     scaffold_app(TESTING_APP, "-r", "damianham/default")
    #     dirs("../../"+TESTING_APP).sort.should eq dirs(APP_TEMPLATE_PATH).sort
    #     cleanup
    #   end
    # end

    describe "Database settings" do
      %w(pg mysql sqlite).each do |db|
        it "generates #{db} correctly" do
          scaffold_app(TESTING_APP, "-d", db)
          set_dir
          %w(development test).each do |env|
            db_adapter = database_yml(env)["adapter"].as_s

            if db == "sqlite"
              # "sets #{db} shards dependencies"
              shard_yml["dependencies"]["jennifer_sqlite3_adapter"].should_not be_nil
            end

            db_key = db == "sqlite" ? "sqlite3" : db
            db_key = db_key == "pg" ? "postgres" : db_key

            # "has correct database connection string"
            db_adapter.should eq db_key
          end
        end
      end
    end

    describe "View templates" do
      it "sets ECR templates" do
        scaffold_app(TESTING_APP, "-t", "ecr")
        set_dir
        launch_yml["language"].should eq "ecr"
        cleanup
      end

      it "it defaults to Slang templates" do
        scaffold_app(TESTING_APP, "-t", "slang")
        set_dir

        launch_yml["language"].should eq "slang"
        cleanup
      end
    end
  end
end

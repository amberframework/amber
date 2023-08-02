require "../../../spec_helper"
require "../../../support/helpers/cli_helper"
require "../../../support/fixtures/cli_fixtures"

include CLIHelper
include CLIFixtures

module Amber::CLI
  describe "amber generate" do
    ENV["AMBER_ENV"] = "test"
    camel_case = "PostComment"
    snake_case = "post_comment"
    incorrect_case = "Post_comment"
    display = "Post Comment"
    class_definition_prefix = "class #{camel_case}"
    spec_definition_prefix = "describe #{camel_case}"

    it "generates controller with correct verbs and actions" do
      scaffold_app(TESTING_APP)
      options = %w(add:post list:get remove:delete)
      MainCommand.run %w(generate controller -y animal) | options
      route_file = File.read("./config/routes.cr")

      # generates controller with correct verbs and actions"
      generated_controller = "./src/controllers/animal_controller.cr"
      File.read(generated_controller).should eq expected_animal_controller

      options.each do |route|
        action, method = route.split(":")
        # "creates a valid #{method} route for #{action}"
        route_file.includes?(build_route("animal", action, method)).should be_true
      end

      # "follows naming conventions for all files and class names"
      [camel_case, snake_case].each do |arg|
        MainCommand.run ["generate", "controller", "-y", arg]
        filename = snake_case
        src_filepath = "./src/controllers/#{filename}_controller.cr"
        spec_filepath = "./spec/controllers/#{filename}_controller_spec.cr"

        File.exists?(src_filepath).should be_true
        File.exists?(spec_filepath).should be_true
        File.read(src_filepath).should contain class_definition_prefix
        File.read(spec_filepath).should contain spec_definition_prefix
        File.delete(src_filepath)
        File.delete(spec_filepath)
      end
      cleanup
    end

    it "generates model correctly" do
      scaffold_app(TESTING_APP)
      MainCommand.run %w(
        generate model -y Post title:string body:text published:bool likes:int user:references
      )

      # "creates Post migration file"
      generated_migration = Dir["./db/migrations/*_post.sql"].first
      File.read(generated_migration).should eq expected_post_model_migration

      # "generates Post model spec file"
      generated_spec = "./spec/models/post_spec.cr"
      File.read(generated_spec).should eq expected_post_model_spec

      # "generates Post model"
      generated_model = "src/models/post.cr"
      File.read(generated_model).should eq expected_post_model
      cleanup
    end

    it "generates scaffold correctly" do
      scaffold_app(TESTING_APP)
      # "follows naming conventions for all files and class names"
      [camel_case, snake_case].each do |arg|
        MainCommand.run ["generate", "scaffold", "-y", arg, "name:string"]

        File.exists?("./spec/models/#{snake_case}_spec.cr").should be_true
        File.exists?("./src/models/#{snake_case}.cr").should be_true
        
        # Recently removed the controller specs, once controller testing is more mature, we'll add them back
        #File.exists?("./spec/controllers/#{snake_case}_controller_spec.cr").should be_true
        File.exists?("./src/controllers/#{snake_case}_controller.cr").should be_true
        File.exists?("./src/views/#{snake_case}/_form.slang").should be_true
        File.exists?("./src/views/#{snake_case}/edit.slang").should be_true
        File.exists?("./src/views/#{snake_case}/index.slang").should be_true
        File.exists?("./src/views/#{snake_case}/new.slang").should be_true
        File.exists?("./src/views/#{snake_case}/show.slang").should be_true
        File.read("./spec/models/#{snake_case}_spec.cr").should contain spec_definition_prefix
        File.read("./src/models/#{snake_case}.cr").should contain class_definition_prefix
        #File.read("./spec/controllers/#{snake_case}_controller_spec.cr").should contain spec_definition_prefix
        File.read("./src/controllers/#{snake_case}_controller.cr").should contain class_definition_prefix
        File.read("./src/views/#{snake_case}/_form.slang").should contain snake_case
        File.read("./src/views/#{snake_case}/edit.slang").should contain display
        File.read("./src/views/#{snake_case}/index.slang").should contain display
        File.read("./src/views/#{snake_case}/new.slang").should contain display
        File.read("./src/views/#{snake_case}/show.slang").should contain snake_case
        File.read("./config/routes.cr").should contain "#{camel_case}Controller"
        File.read("./config/routes.cr").should_not contain "#{incorrect_case}Controller"
      end
      cleanup
    end

    it "generates migrations correctly" do
      scaffold_app(TESTING_APP)
      # "follows naming conventions for all files"
      [camel_case, snake_case].each do |arg|
        MainCommand.run ["generate", "migration", "-y", arg]

        migration_filename = Dir.entries("./db/migrations").sort.last
        migration_filename.should contain snake_case
        File.delete("./db/migrations/#{migration_filename}")
      end
      cleanup
    end

    it "generates mailers correctly" do
      scaffold_app(TESTING_APP)
      # "follows naming conventions for all files and class names"
      [camel_case, snake_case].each do |arg|
        MainCommand.run ["generate", "mailer", "-y", arg]
        filename = snake_case
        src_filepath = "./src/mailers/#{filename}_mailer.cr"

        File.exists?(src_filepath).should be_true
        File.read(src_filepath).should contain class_definition_prefix
        File.delete(src_filepath)
      end
      cleanup
    end

    it "generatres socket correctly" do
      scaffold_app(TESTING_APP)
      struct_definition_prefix = "struct #{camel_case}"

      # "follows naming conventions for all files and class names"
      [camel_case, snake_case].each do |arg|
        MainCommand.run ["generate", "socket", "-y", arg]
        filename = snake_case
        src_filepath = "./src/sockets/#{filename}_socket.cr"

        File.exists?(src_filepath).should be_true
        File.read(src_filepath).should contain struct_definition_prefix
        File.delete(src_filepath)
      end
      cleanup
    end

    it "generates channels correctly" do
      scaffold_app(TESTING_APP)
      # "follows naming conventions for all files and class names"
      [camel_case, snake_case].each do |arg|
        MainCommand.run ["generate", "channel", "-y", arg]
        filename = snake_case
        src_filepath = "./src/channels/#{filename}_channel.cr"

        File.exists?(src_filepath).should be_true
        File.read(src_filepath).should contain class_definition_prefix
        File.delete(src_filepath)
      end
      cleanup
    end

    it "generates auth correctly" do
      scaffold_app(TESTING_APP)

      camel_case = "AdminUser"
      snake_case = "admin_user"
      class_definition_prefix = "class #{camel_case}"
      spec_definition_prefix = "describe #{camel_case}"
      migration_definition_prefix = "CREATE TABLE #{snake_case}"

      # "follows naming conventions for all files and class names"
      [camel_case, snake_case].each do |arg|
        MainCommand.run ["generate", "auth", "-y", arg]

        File.exists?("./db/seeds.cr").should be_true
        File.exists?("./spec/models/admin_user_spec.cr").should be_true
        File.exists?("./src/controllers/session_controller.cr").should be_true
        File.exists?("./src/pipes/authenticate.cr").should be_true
        File.exists?("./src/models/admin_user.cr").should be_true
        File.exists?("./src/views/admin_user/new.slang").should be_true
        File.exists?("./src/views/session/new.slang").should be_true

        migration_filename = Dir["./db/migrations/*_#{snake_case}.sql"].first
        File.read("#{migration_filename}").should contain migration_definition_prefix
        File.read("./db/seeds.cr").should contain camel_case
        File.read("./spec/models/admin_user_spec.cr").should contain spec_definition_prefix
        File.read("./src/controllers/session_controller.cr").should contain camel_case
        File.read("./src/controllers/session_controller.cr").should contain snake_case
        File.read("./src/pipes/authenticate.cr").should contain camel_case
        File.read("./src/pipes/authenticate.cr").should contain snake_case
        File.read("./src/models/admin_user.cr").should contain class_definition_prefix
        File.read("./src/models/admin_user.cr").should contain snake_case
        File.read("./src/views/admin_user/new.slang").should contain snake_case
        File.read("./src/views/session/new.slang").should contain snake_case
      end
      cleanup
    end
  end
end

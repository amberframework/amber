require "../../../spec_helper"

module Amber::CLI
  begin
    describe MainCommand::Generate do
      context "scaffold" do
        it "generates and compile generated app" do
          ENV["AMBER_ENV"] = "test"
          MainCommand.run ["new", TESTING_APP]
          Dir.cd(TESTING_APP)
          MainCommand.run ["generate", "scaffold", "Animal", "name:string"]
          Amber::CLI::Spec.prepare_yaml(Dir.current)

          `shards build`

          File.exists?("bin/#{TEST_APP_NAME}").should be_true

          Amber::CLI::Spec.cleanup
        end

        it "follows naming conventions for all files and class names" do
          ENV["AMBER_ENV"] = "test"
          Amber::CLI::MainCommand.run ["new", TESTING_APP]
          Dir.cd(TESTING_APP)

          camel_case = "PostComment"
          snake_case = "post_comment"
          class_definition_prefix = "class #{camel_case}"
          spec_definition_prefix = "describe #{camel_case}"

          [camel_case, snake_case].each do |arg|
            MainCommand.run ["generate", "scaffold", arg, "name:string"]

            File.exists?("./spec/models/#{snake_case}_spec.cr").should be_true
            File.exists?("./src/models/#{snake_case}.cr").should be_true
            File.exists?("./spec/controllers/#{snake_case}_controller_spec.cr").should be_true
            File.exists?("./src/controllers/#{snake_case}_controller.cr").should be_true
            File.exists?("./src/views/#{snake_case}/_form.slang").should be_true
            File.exists?("./src/views/#{snake_case}/edit.slang").should be_true
            File.exists?("./src/views/#{snake_case}/index.slang").should be_true
            File.exists?("./src/views/#{snake_case}/new.slang").should be_true
            File.exists?("./src/views/#{snake_case}/show.slang").should be_true

            File.read("./spec/models/#{snake_case}_spec.cr").should contain spec_definition_prefix
            File.read("./src/models/#{snake_case}.cr").should contain class_definition_prefix
            File.read("./spec/controllers/#{snake_case}_controller_spec.cr").should contain spec_definition_prefix
            File.read("./src/controllers/#{snake_case}_controller.cr").should contain class_definition_prefix
            File.read("./src/views/#{snake_case}/_form.slang").should contain snake_case
            File.read("./src/views/#{snake_case}/edit.slang").should contain camel_case
            File.read("./src/views/#{snake_case}/index.slang").should contain camel_case
            File.read("./src/views/#{snake_case}/new.slang").should contain camel_case
            File.read("./src/views/#{snake_case}/show.slang").should contain snake_case

            File.delete("./spec/models/#{snake_case}_spec.cr")
            File.delete("./src/models/#{snake_case}.cr")
            File.delete("./spec/controllers/#{snake_case}_controller_spec.cr")
            File.delete("./src/controllers/#{snake_case}_controller.cr")
            File.delete("./src/views/#{snake_case}/_form.slang")
            File.delete("./src/views/#{snake_case}/edit.slang")
            File.delete("./src/views/#{snake_case}/index.slang")
            File.delete("./src/views/#{snake_case}/new.slang")
            File.delete("./src/views/#{snake_case}/show.slang")
          end
          Amber::CLI::Spec.cleanup
        end
      end

      context "model" do
        ENV["AMBER_ENV"] = "test"
        Amber::CLI::MainCommand.run ["new", TESTING_APP]
        Dir.cd(TESTING_APP)

        it "follows naming conventions for all files and class names" do
          camel_case = "PostComment"
          snake_case = "post_comment"
          class_definition_prefix = "class #{camel_case}"
          spec_definition_prefix = "describe #{camel_case}"

          [camel_case, snake_case].each do |arg|
            MainCommand.run ["generate", "model", arg]
            filename = snake_case
            src_filepath = "./src/models/#{filename}.cr"
            spec_filepath = "./spec/models/#{filename}_spec.cr"

            File.exists?(src_filepath).should be_true
            File.exists?(spec_filepath).should be_true
            File.read(src_filepath).should contain class_definition_prefix
            File.read(spec_filepath).should contain spec_definition_prefix
            File.delete(src_filepath)
            File.delete(spec_filepath)
          end
        end
        Amber::CLI::Spec.cleanup
      end

      context "controller" do
        ENV["AMBER_ENV"] = "test"
        Amber::CLI::MainCommand.run ["new", TESTING_APP]
        Dir.cd(TESTING_APP)

        it "generates controller with correct verbs and actions" do
          MainCommand.run ["generate", "controller", "Animal", "add:post", "list:get", "remove:delete"]
          routes_post = %(post "/animal/add", AnimalController, :add)
          routes_get = %(get "/animal/list", AnimalController, :list)
          routes_delete = %(delete "/animal/remove")

          output_class = <<-CONT
          class AnimalController < ApplicationController
            def add
              render("add.slang")
            end

            def list
              render("list.slang")
            end

            def remove
              render("remove.slang")
            end
          end

          CONT

          File.read("./config/routes.cr").should contain routes_post
          File.read("./config/routes.cr").should contain routes_get
          File.read("./config/routes.cr").should contain routes_delete
          File.read("./src/controllers/animal_controller.cr").should eq output_class

          Amber::CLI::Spec.cleanup
        end

        it "follows naming conventions for all files and class names" do
          ENV["AMBER_ENV"] = "test"
          Amber::CLI::MainCommand.run ["new", TESTING_APP]
          Dir.cd(TESTING_APP)
          camel_case = "PostComment"
          snake_case = "post_comment"
          class_definition_prefix = "class #{camel_case}"
          spec_definition_prefix = "describe #{camel_case}"

          [camel_case, snake_case].each do |arg|
            MainCommand.run ["generate", "controller", arg]
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
        end
        Amber::CLI::Spec.cleanup
      end

      context "migration" do
        ENV["AMBER_ENV"] = "test"
        Amber::CLI::MainCommand.run ["new", TESTING_APP]
        Dir.cd(TESTING_APP)

        it "follows naming conventions for all files" do
          camel_case = "PostComment"
          snake_case = "post_comment"
          migration_definition_prefix = "CREATE TABLE #{snake_case}"

          [camel_case, snake_case].each do |arg|
            MainCommand.run ["generate", "migration", arg]

            migration_filename = Dir.entries("./db/migrations").sort.last
            migration_filename.should contain snake_case
            File.delete("./db/migrations/#{migration_filename}")
          end
        end
        Amber::CLI::Spec.cleanup
      end

      context "mailer" do
        ENV["AMBER_ENV"] = "test"
        Amber::CLI::MainCommand.run ["new", TESTING_APP]
        Dir.cd(TESTING_APP)

        it "follows naming conventions for all files and class names" do
          camel_case = "PostComment"
          snake_case = "post_comment"
          class_definition_prefix = "class #{camel_case}"
          spec_definition_prefix = "describe #{camel_case}"

          [camel_case, snake_case].each do |arg|
            MainCommand.run ["generate", "mailer", arg]
            filename = snake_case
            src_filepath = "./src/mailers/#{filename}_mailer.cr"

            File.exists?(src_filepath).should be_true
            File.read(src_filepath).should contain class_definition_prefix
            File.delete(src_filepath)
          end
        end
        Amber::CLI::Spec.cleanup
      end

      context "socket" do
        ENV["AMBER_ENV"] = "test"
        Amber::CLI::MainCommand.run ["new", TESTING_APP]
        Dir.cd(TESTING_APP)

        it "follows naming conventions for all files and class names" do
          camel_case = "PostComment"
          snake_case = "post_comment"
          struct_definition_prefix = "struct #{camel_case}"

          [camel_case, snake_case].each do |arg|
            MainCommand.run ["generate", "socket", arg]
            filename = snake_case
            src_filepath = "./src/sockets/#{filename}_socket.cr"

            File.exists?(src_filepath).should be_true
            File.read(src_filepath).should contain struct_definition_prefix
            File.delete(src_filepath)
          end
        end
        Amber::CLI::Spec.cleanup
      end

      context "channel" do
        ENV["AMBER_ENV"] = "test"
        Amber::CLI::MainCommand.run ["new", TESTING_APP]
        Dir.cd(TESTING_APP)

        it "follows naming conventions for all files and class names" do
          camel_case = "PostComment"
          snake_case = "post_comment"
          class_definition_prefix = "class #{camel_case}"
          spec_definition_prefix = "describe #{camel_case}"

          [camel_case, snake_case].each do |arg|
            MainCommand.run ["generate", "channel", arg]
            filename = snake_case
            src_filepath = "./src/channels/#{filename}_channel.cr"

            File.exists?(src_filepath).should be_true
            File.read(src_filepath).should contain class_definition_prefix
            File.delete(src_filepath)
          end
        end
        Amber::CLI::Spec.cleanup
      end

      context "auth" do
        ENV["AMBER_ENV"] = "test"
        Amber::CLI::MainCommand.run ["new", TESTING_APP]
        Dir.cd(TESTING_APP)

        it "follows naming conventions for all files and class names" do
          camel_case = "AdminUser"
          snake_case = "admin_user"
          class_definition_prefix = "class #{camel_case}"
          spec_definition_prefix = "describe #{camel_case}"
          migration_definition_prefix = "CREATE TABLE #{snake_case}"

          [camel_case, snake_case].each do |arg|
            MainCommand.run ["generate", "auth", arg]

            File.exists?("./db/seeds.cr").should be_true
            File.exists?("./spec/models/admin_user_spec.cr").should be_true
            File.exists?("./src/controllers/registration_controller.cr").should be_true
            File.exists?("./src/controllers/session_controller.cr").should be_true
            File.exists?("./src/handlers/authenticate.cr").should be_true
            File.exists?("./src/models/admin_user.cr").should be_true
            File.exists?("./src/views/registration/new.slang").should be_true
            File.exists?("./src/views/session/new.slang").should be_true

            migration_filename = Dir.entries("./db/migrations").sort.last
            File.read("./db/migrations/#{migration_filename}").should contain migration_definition_prefix
            File.read("./db/seeds.cr").should contain camel_case
            File.read("./db/seeds.cr").should contain snake_case
            File.read("./spec/models/admin_user_spec.cr").should contain spec_definition_prefix
            File.read("./src/controllers/registration_controller.cr").should contain camel_case
            File.read("./src/controllers/registration_controller.cr").should contain snake_case
            File.read("./src/controllers/session_controller.cr").should contain camel_case
            File.read("./src/controllers/session_controller.cr").should contain snake_case
            File.read("./src/handlers/authenticate.cr").should contain camel_case
            File.read("./src/handlers/authenticate.cr").should contain snake_case
            File.read("./src/models/admin_user.cr").should contain class_definition_prefix
            File.read("./src/models/admin_user.cr").should contain snake_case
            File.read("./src/views/registration/new.slang").should contain snake_case
            File.read("./src/views/session/new.slang").should contain snake_case

            File.delete("./db/migrations/#{migration_filename}")
            File.delete("./db/seeds.cr")
            File.delete("./spec/models/admin_user_spec.cr")
            File.delete("./src/controllers/registration_controller.cr")
            File.delete("./src/controllers/session_controller.cr")
            File.delete("./src/handlers/authenticate.cr")
            File.delete("./src/models/admin_user.cr")
            File.delete("./src/views/registration/new.slang")
            File.delete("./src/views/session/new.slang")
          end
        end
        Amber::CLI::Spec.cleanup
      end
    end
  ensure
    Amber::CLI::Spec.cleanup
  end
end

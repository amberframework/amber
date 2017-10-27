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
      end

      context "controllers" do
        it "generates controller with correct verbs and actions" do
          ENV["AMBER_ENV"] = "test"
          MainCommand.run ["new", TESTING_APP]
          Dir.cd(TESTING_APP)
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

          File.read("./config/routes.cr").includes?(routes_post).should be_true
          File.read("./config/routes.cr").includes?(routes_get).should be_true
          File.read("./config/routes.cr").includes?(routes_delete).should be_true
          File.read("./src/controllers/animal_controller.cr").should eq output_class

          Amber::CLI::Spec.cleanup
        end
      end
    end
  ensure
    Amber::CLI::Spec.cleanup
  end
end

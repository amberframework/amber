require "../../spec_helper"

begin
  describe Amber::CMD do
    context "Init command" do
      it "should generate controller with correct verbs and actions" do
        Amber::CMD::MainCommand.run ["new", TESTING_APP]
        Dir.cd(TESTING_APP)
        Amber::CMD::MainCommand.run ["generate", "controller", "Animal", "add:post", "list:get", "remove:delete"]
        expected = <<-CONT
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

        File.read("src/controllers/animal_controller.cr").should eq expected
      end

      it "should generate routes with correct verbs and actions" do
        expected = ["post \"/animal/add\", AnimalController, :add\n    get \"/animal/list\", AnimalController, :list\n    delete \"/animal/remove\""]
        File.read("config/routes.cr").scan(expected.first).should eq expected
      end
    end
  end
ensure
  Amber::CMD::Spec.cleanup
end

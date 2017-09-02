require "../../spec_helper"

Spec.after_each do
  Amber::CLI::Spec.cleanup
end

module Amber::CLI
  describe MainCommand do
    context "application structure" do
      it "creates amber directory structure" do
        MainCommand.run ["new", TESTING_APP]

        Dir.exists?(TESTING_APP).should be_true
        dirs(TESTING_APP).sort.should eq dirs(APP_TPL_PATH).sort
        db_yml["pg"].should_not be_nil
        shard_yml["dependencies"]["pg"].should_not be_nil
        amber_yml["language"].should eq "slang"
      end
    end

    context "database" do
      it "create app with mysql settings" do
        MainCommand.run ["new", TESTING_APP, "-d", "mysql", "-t", "ecr"]

        db_yml["mysql"].should_not be_nil
        shard_yml["dependencies"]["mysql"].should_not be_nil
        amber_yml["language"].should eq "ecr"
      end

      it "creates app with sqlite settings" do
        MainCommand.run ["new", TESTING_APP, "-d", "sqlite"]

        db_yml["sqlite"].should_not be_nil
        shard_yml["dependencies"]["sqlite3"].should_not be_nil
      end

      it "generates and compile generated app" do
        MainCommand.run ["new", TESTING_APP, "--deps"]
        Dir.cd(TESTING_APP)
        MainCommand.run ["generate", "scaffold", "Animal", "name:string"]
        prepare_yaml(Dir.current)
        `rm shard.lock`
        `shards build`

        File.exists?("bin/#{TESTING_APP}").should be_true
      end
    end

    context "controllers" do
      it "should generate controller with correct verbs and actions" do
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
      end
    end
  end
end

def dirs(for app)
  gen_dirs = Dir.glob("#{app}/**/*").select { |e| Dir.exists? e }
  gen_dirs.map { |dir| dir[(app.size + 1)..-1] }
end

def db_yml
  YAML.parse(File.read("#{TESTING_APP}/config/database.yml"))
end

def amber_yml
  YAML.parse(File.read("#{TESTING_APP}/.amber.yml"))
end

def shard_yml
  YAML.parse(File.read("#{TESTING_APP}/shard.yml"))
end

def prepare_yaml(path)
  shard = File.read("#{path}/shard.yml")
  shard = shard.gsub(/github\:\samber\-crystal\/amber\n/, "path: ../")
  File.write("#{path}/shard.yml", shard)
end

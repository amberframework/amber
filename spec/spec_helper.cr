# NOTE: Constants should be set before require begins.

ENV["AMBER_ENV"] = "test"
TEST_PATH     = "spec/support/sample"
PUBLIC_PATH   = TEST_PATH + "/public"
VIEWS_PATH    = TEST_PATH + "/views"
TEST_APP_NAME = "test_app"
TESTING_APP   = "./tmp/#{TEST_APP_NAME}"
APP_TPL_PATH  = "./src/amber/cli/templates/app"
CURRENT_DIR   = Dir.current

require "http"
require "spec"
require "../src/amber"
require "../src/amber/cli/commands"
require "./amber/controller/*"
require "./support/**"

module Amber::CLI::Spec
  extend self

  def cleanup
    puts "cleaning up..."
    Dir.cd CURRENT_DIR
    `rm -rf #{TESTING_APP}`
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
    shard = shard.gsub("github: amberframework/amber\n", "path: ../../\n")
    File.write("#{path}/shard.yml", shard)
  end
end

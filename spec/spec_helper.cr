# NOTE: Constants should be set before require begins.

ENV["AMBER_ENV"] = "test"
TEST_PATH     = "spec/support/sample"
PUBLIC_PATH   = TEST_PATH + "/public"
VIEWS_PATH    = TEST_PATH + "/views"
TEST_APP_NAME = "sample-app"
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

  def db_name(db_url : String) : String
    db_name(URI.parse(db_url))
  end

  def db_name(db_uri : URI) : String
    path = db_uri.path
    path ? path.split('/').last : ""
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

  def environment_yml(environment : String)
    YAML.parse(File.read("#{TESTING_APP}/config/environments/#{environment}.yml"))
  end

  def development_yml
    environment_yml("development")
  end

  def production_yml
    environment_yml("production")
  end

  def test_yml
    environment_yml("test")
  end

  def docker_compose_yml
    YAML.parse(File.read("#{TESTING_APP}/docker-compose.yml"))
  end

  def prepare_yaml(path)
    shard = File.read("#{path}/shard.yml")
    shard = shard.gsub("github: amberframework/amber\n", "path: ../../\n")
    File.write("#{path}/shard.yml", shard)
  end
end

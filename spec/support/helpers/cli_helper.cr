require "file_utils"
require "json"
require "json_mapping"

class RouteJSON
  JSON.mapping({
    verb:        String,
    controller:  String,
    action:      String,
    pipeline:    String,
    scope:       String,
    uri_pattern: String,
  })
end

module CLIHelper
  BASE_ENV_PATH       = "./config/environments/"
  ENV_CONFIG_PATH     = "#{TESTING_APP}/config/environments/"
  CURRENT_ENVIRONMENT = ENV["AMBER_ENV"] ||= "test"
  ENVIRONMENTS        = %w(development test)

  def cleanup
    Dir.cd CURRENT_DIR
    if Dir.exists?(TESTING_APP)
      FileUtils.rm_rf(TESTING_APP)
    end
  end

  def prepare_test_app
    cleanup
    scaffold_app(TESTING_APP, "-d", "sqlite")
    environment_yml(CURRENT_ENVIRONMENT, "#{Dir.current}/config/environments/")
  end

  def dirs(for app)
    gen_dirs = Dir.glob("#{app}/**/*").select { |e| Dir.exists? e }
    gen_dirs.map { |dir| dir[(app.size + 1)..-1] }
  end

  def expected_db_url(db_key, env)
    case db_key
    when "pg"
      "postgres://postgres:password@localhost:5432/#{TEST_APP_NAME}_#{env}"
    when "mysql"
      "#{db_key}://root@localhost:3306/#{TEST_APP_NAME}_#{env}"
    else
      "#{db_key}:./db/#{TEST_APP_NAME}_#{env}.db"
    end
  end

  def db_name(db_url : String) : String
    db_name(URI.parse(db_url))
  end

  def db_name(db_uri : URI) : String
    path = db_uri.path || db_uri.opaque
    path ? path.split('/').last : ""
  end

  def db_yml(path = CURRENT_ENV_PATH)
    YAML.parse(File.read(path))
  end

  def amber_yml(path = TESTING_APP)
    YAML.parse(File.read("#{path}/.amber.yml"))
  end

  def shard_yml(path = TESTING_APP)
    YAML.parse(File.read("#{path}/shard.yml"))
  end

  def environment_yml(environment : String, path = ENV_CONFIG_PATH)
    YAML.parse(File.read("#{path}#{environment}.yml"))
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
    if File.exists?("#{path}/shard.yml")
      shard = File.read("#{path}/shard.yml")
      shard = shard.gsub(/github\:\samberframework\/amber\n.*(?=\n)/, "path: ../../../amber")
      File.write("#{path}/shard.yml", shard)
    end
  end

  def prepare_db_yml(path = ENV_CONFIG_PATH)
    db_yml = File.read("#{path}#{CURRENT_ENVIRONMENT}.yml")
    db_yml = db_yml.gsub("@localhost:5432", "@db:5432")
    File.write("#{path}#{CURRENT_ENVIRONMENT}.yml", db_yml)
  end

  def recipe_app(app_name, *options)
    Amber::CLI::MainCommand.run ["new", app_name, "-y"] | options.to_a
    Dir.cd(app_name)
    prepare_yaml(Dir.current)
  end

  def scaffold_app(app_name, *options)
    Amber::CLI::MainCommand.run ["new", app_name, "-y", "--no-deps"] | options.to_a
    Dir.cd(app_name)
    prepare_yaml(Dir.current)
  end

  def build_route(controller, action, method)
    %(#{method} "/#{controller.downcase}/#{action}", #{controller.capitalize}Controller, :#{action})
  end

  def route_table_rows(route_table_text)
    route_table_text.split("\n").reject { |line| line =~ /(─┼─|═╦═|═╩═)/ }
  end

  def route_table_from_json(route_table_json)
    Array(RouteJSON).from_json(route_table_json)
  end
end

module CLIHelper
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
    path = db_uri.path || db_uri.opaque
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

  def scaffold_app(app_name, *options)
    Amber::CLI::MainCommand.run ["new", app_name] | options.to_a
    Dir.cd(app_name)
    prepare_yaml(Dir.current)
  end

  def build_route(controller, action, method)
    %(#{method} "/#{controller.downcase}/#{action}", #{controller.capitalize}Controller, :#{action})
  end
end

module CLIHelper
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

  def generate_app(app_name)

	end
end

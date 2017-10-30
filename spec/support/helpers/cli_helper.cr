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

  def scaffold_app(app_name)
    Amber::CLI::MainCommand.run ["new", app_name]
    Dir.cd(app_name)
    prepare_yaml(Dir.current)
  end

  def build_route(controller, action, method)
    %(#{method} "/#{controller.downcase}/#{action}", #{controller.capitalize}Controller, :#{action})
  end

  def assert_app_compiled?(app_name)
    `shards build`
    File.exists?("bin/#{app_name}").should be_true
  end

  def assert_controller_generated?(controller, options, expected_controller)
    route_file = File.read("./config/routes.cr")
    options.each do |route|
      action, method = route.split(":")
      assert_route_generated? route_file, build_route(controller, action, method)
    end

    File.read("./src/controllers/#{controller.downcase}_controller.cr").should eq expected_controller
  end

  def assert_route_generated?(route_file, route)
    route_file.includes?(route).should be_true
  end

  def assert_encrypted_files_exists?(enc_file, enc_key)
    File.exists?("config/environments/#{enc_file}").should be_true
    File.read(enc_key).size.should eq 44
  end

  def assert_app_directory_structure?(app_path, expected_app_path)
    dirs(app_path).sort.should eq dirs(expected_app_path).sort
  end

  def assert_correct_db_settings?(db_type)
    db_yml[db_type].should_not be_nil
    shard_yml["dependencies"][db_type].should_not be_nil
  end

  def assert_correct_template_settings?(template_type)
    amber_yml["language"].should eq template_type
  end
end

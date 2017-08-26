require "./spec_helper"

# TODO: Perhaps some of these tests are redundant.
begin
  describe Amber::CMD do
    Spec.after_each do
      puts "cleaning up..."
      Dir.cd(CURRENT_DIR)
      `rm -rf #{TESTING_APP}`
    end

    context "Init command" do
      it "should create the new project" do
        Amber::CMD::MainCommand.run ["new", TESTING_APP]
        Dir.exists?(TESTING_APP).should be_true
      end

      it "should create the structure" do
        Amber::CMD::MainCommand.run ["new", TESTING_APP]
        dirs = Dir.glob("#{APP_TPL_PATH}/**/*").select { |e| Dir.exists? e }
        rel_dirs = dirs.map { |dir| dir[(APP_TPL_PATH.size + 1)..-1] }

        gen_dirs = Dir.glob("#{TESTING_APP}/**/*").select { |e| Dir.exists? e }
        rel_gen_dirs = gen_dirs.map { |dir| dir[(TESTING_APP.size + 1)..-1] }

        rel_dirs.sort.should eq rel_gen_dirs.sort
        YAML.parse(File.read("#{TESTING_APP}/config/database.yml"))["pg"].should_not be_nil
        YAML.parse(File.read("#{TESTING_APP}/shard.yml"))["dependencies"]["pg"].should_not be_nil
      end

      it "should create app with mysql settings" do
        Amber::CMD::MainCommand.run ["new", TESTING_APP, "-d", "mysql"]
        YAML.parse(File.read("#{TESTING_APP}/config/database.yml"))["mysql"].should_not be_nil
        YAML.parse(File.read("#{TESTING_APP}/shard.yml"))["dependencies"]["mysql"].should_not be_nil
      end

      it "should create app with sqlite settings" do
        Amber::CMD::MainCommand.run ["new", TESTING_APP, "-d", "sqlite"]
        YAML.parse(File.read("#{TESTING_APP}/config/database.yml"))["sqlite"].should_not be_nil
        YAML.parse(File.read("#{TESTING_APP}/shard.yml"))["dependencies"]["sqlite3"].should_not be_nil
      end

      it "should generate .amber.yml with language settings" do
        Amber::CMD::MainCommand.run ["new", TESTING_APP, "-t", "ecr"]
        YAML.parse(File.read("#{TESTING_APP}/.amber.yml"))["language"].should eq "ecr"
      end

      # TODO: uncomment when the new build is in master
      # it "should require files in the right order and compile" do
      #   Amber::CMD::MainCommand.run ["new", TESTING_APP, "--deps"]
      #   Dir.cd(TESTING_APP)
      #   Amber::CMD::MainCommand.run ["generate", "scaffold", "Animal", "name:string"]
      #   `shards build`
      #   File.exists?("bin/testapp").should be_true
      # end
    end
  end
ensure
  puts "Recoving from exception and removing test code.."
  Dir.cd(CURRENT_DIR)
  `rm -rf #{TESTING_APP}`
end

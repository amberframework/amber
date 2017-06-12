require "./spec_helper"

describe Amber::CMD do
  context "Init command" do
    it "should create the new project" do
      Amber::CMD::MainCommand.run ["new", TESTING_APP]
      Dir.exists?(TESTING_APP).should be_true
      `rm -rf #{TESTING_APP}`
    end

    it "should create the structure" do
      Amber::CMD::MainCommand.run ["new", TESTING_APP]
      dirs = Dir.glob("#{APP_TPL_PATH}/**/*").select { |e| Dir.exists? e }
      rel_dirs = dirs.map { |dir| dir[(APP_TPL_PATH.size + 1)..-1] }

      gen_dirs = Dir.glob("#{TESTING_APP}/**/*").select { |e| Dir.exists? e }
      rel_gen_dirs = gen_dirs.map { |dir| dir[(TESTING_APP.size + 1)..-1] }

      rel_dirs.sort.should eq rel_gen_dirs.sort
      File.read_lines("#{TESTING_APP}/config/database.yml").first.should eq "pg:"
      File.read_lines("#{TESTING_APP}/shard.yml")[26]?.should eq "  pg:"
      `rm -rf #{TESTING_APP}`
    end

    it "should create app with mysql settings" do
      Amber::CMD::MainCommand.run ["new", TESTING_APP, "-d", "mysql"]
      File.read_lines("#{TESTING_APP}/config/database.yml").first.should eq "mysql:"
      File.read_lines("#{TESTING_APP}/shard.yml")[26]?.should eq "  mysql:"
      `rm -rf #{TESTING_APP}`
    end

    it "should create app with sqlite settings" do
      Amber::CMD::MainCommand.run ["new", TESTING_APP, "-d", "sqlite"]
      File.read_lines("#{TESTING_APP}/config/database.yml").first.should eq "sqlite:"
      File.read_lines("#{TESTING_APP}/shard.yml")[26]?.should eq "  sqlite3:"
      `rm -rf #{TESTING_APP}`
    end

    it "should generate .amber.yml with language settings" do
      Amber::CMD::MainCommand.run ["new", TESTING_APP, "-t", "ecr"]
      File.read_lines("#{TESTING_APP}/.amber.yml")[2]?.should eq "language: ecr"
      `rm -rf #{TESTING_APP}`
    end
  end
end

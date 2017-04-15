require "./spec_helper"

describe Kemalyst::Generator do
  context "Init command" do
    it "should create the new project" do
      Kemalyst::Generator::MainCommand.run ["init", "app", TESTING_APP]
      Dir.exists?(TESTING_APP).should be_true
      `rm -rf #{TESTING_APP}`
    end

    it "should create the structure" do
      Kemalyst::Generator::MainCommand.run ["init", "app", TESTING_APP]
      dirs = Dir.glob("#{APP_TPL_PATH}/**/*").select {|e| Dir.exists? e }
      rel_dirs = dirs.map { |dir| dir[(APP_TPL_PATH.size+1)..-1] }

      gen_dirs = Dir.glob("#{TESTING_APP}/**/*").select { |e| Dir.exists? e }
      rel_gen_dirs = gen_dirs.map { |dir| dir[(TESTING_APP.size+1)..-1] }

      rel_dirs.sort.should eq rel_gen_dirs.sort
      File.read_lines("#{TESTING_APP}/config/database.yml").first.should eq "pg:"
      File.read_lines("#{TESTING_APP}/shard.yml")[13]?.should eq "  pg:"
      `rm -rf #{TESTING_APP}`
    end

    it "should create it with mysql settings" do
      Kemalyst::Generator::MainCommand.run ["init", "app", TESTING_APP, "--db", "mysql"]
      File.read_lines("#{TESTING_APP}/config/database.yml").first.should eq "mysql:"
      File.read_lines("#{TESTING_APP}/shard.yml")[13]?.should eq "  mysql:"
      `rm -rf #{TESTING_APP}`
    end
  end
end

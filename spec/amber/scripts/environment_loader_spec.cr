require "../../../spec_helper"

describe Amber::Server do
  describe "environment" do
    it "should load expected output" do
      expected = <<-EXP
      @name = "amber_test_app"
      @port_reuse = true
      @process_count = (ENV[%(AMBER_PROCESS_COUNT)]? || 1).to_i
      @log = ::Logger.new(STDOUT).tap{|l| l.level = ::Logger::INFO}
      @color = true
      @redis_url = "\#{ENV[%(REDIS_URL)]? || %(redis://localhost:6379)}"
      @database_url = "mysql://root@localhost:3306/amber_test_app_test"
      @port = (ENV["PORT"] ||= "3000").to_i
      @host = "0.0.0.0"
      @secret_key_base = "mV6kTmG3k1yVFh-fPYpugSn0wbZveDvrvfQuv88DPF8"
      @session = {
        :key => "amber.session",
        :store => :signed_cookie,
        :expires => 0,
      }
      getter secrets = {"description": "Store your test secrets credentials and settings here."}

      EXP
      {{run("../../../src/amber/scripts/environment_loader.cr", "test").stringify}}.should eq expected
    end

    it "should load default settings when environment file doesn't exist." do
      expected = <<-EXP
      @name = "Amber_App"
      @port_reuse = true
      @process_count = 1
      @log = ::Logger.new(STDOUT).tap{|l| l.level = ::Logger::INFO}
      @color = true
      @redis_url = "redis://localhost:6379"
      @database_url = ""
      @port = 3000
      @host = "127.0.0.1"
      @session = {:key => "amber.session", :store => :signed_cookie, :expires => 0}
      getter secrets = {description: "Store your non_existent secrets credentials and settings here."}

      EXP
      # Removed secret_key_base from default settings since it's different everytime.
      {{run("../../../src/amber/scripts/environment_loader.cr", "non_existent").stringify}}.gsub(/@secret_key_base[^\n]+\n/, "").should eq expected
    end
  end
end

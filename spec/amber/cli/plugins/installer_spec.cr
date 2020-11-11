require "../../../spec_helper"
require "../../../support/helpers/cli_helper"

include CLIHelper

module Amber::Plugins
  describe Installer do
    Spec.after_each do
      cleanup
    end

    it "should add routes when installing plugin" do
      scaffold_app_with_plugin

      Installer.new("test", [] of String).render("#{Dir.current}/src/plugins", list: true, color: true)

      routes = File.read("#{Dir.current}/config/routes.cr")
      routes.empty?.should be_false
      routes.should contain "post \"/plugin\", PluginController, :create"
      routes.should contain "plug Authenticate.new"
    end

    it "should pass args to liquid context" do
      scaffold_app_with_plugin
      installer = Installer.new("test", ["Amber"])
      installer.render("#{Dir.current}/src/plugins", list: true, color: true)

      installer.settings.should_not be_nil
      installer.args["name"]?.should_not be_nil
      installer.args["name"].should eq "Amber"
    end

    it "should clean up config.yml after rendering" do
      scaffold_app_with_plugin
      Installer.new("test", [] of String).render("#{Dir.current}/src/plugins", list: true, color: true)
      File.exists?("#{Dir.current}/src/plugins/config.yml").should be_false
    end
  end
end

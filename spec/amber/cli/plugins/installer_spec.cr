require "../../../spec_helper"
require "../../../support/helpers/cli_helper"

include CLIHelper

module Amber::Plugins
  describe Installer do
    Spec.after_each do
      cleanup
    end

    it "should add routes when installing plugin" do
      scaffold_app(TESTING_APP)
      Dir.mkdir_p("#{Dir.current}/lib/test/plugin")
      File.write("#{Dir.current}/lib/test/plugin/config.yml", yml_config_contents)

      Installer.new("test").render("#{Dir.current}/src/plugins", list: true, color: true)

      routes = File.read("#{Dir.current}/config/routes.cr")
      routes.empty?.should be_false
      routes.should contain "post \"/plugin\", PluginController, :create"
    end
  end
end

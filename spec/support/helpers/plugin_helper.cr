module PluginHelper
  def yml_config_contents
    <<-FILE
      routes:
        plugs:
          web:
            - plug Authenticate.new
        pipelines:
          web:
            - post "/plugin", PluginController, :create
      args:
        - name
    FILE
  end

  def scaffold_app_with_plugin
    scaffold_app(TESTING_APP)
    Dir.mkdir_p("#{Dir.current}/lib/test/plugin")
    File.write("#{Dir.current}/lib/test/plugin/config.yml", yml_config_contents)
  end
end

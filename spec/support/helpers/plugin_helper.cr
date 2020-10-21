module PluginHelper
  def yml_config_contents
    <<-FILE
      routes:
        pipelines:
          web:
            - post "/plugin", PluginController, :create
    FILE
  end
end

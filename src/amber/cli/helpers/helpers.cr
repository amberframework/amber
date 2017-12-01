module Amber::CLI::Helpers
  def add_routes(pipeline, route)
    routes = File.read("./config/routes.cr")
    replacement = <<-ROUTES
    routes :#{pipeline.to_s} do
      #{route}
    ROUTES
    File.write("./config/routes.cr", routes.gsub("routes :#{pipeline.to_s} do", replacement))
  end

  def add_plugs(pipeline, plug)
    routes = File.read("./config/routes.cr")
    return if routes.includes? plug

    pipes = routes.match(/pipeline :#{pipeline.to_s} do(.+?)end/m)
    return unless pipes

    replacement = <<-PLUGS
    pipeline :#{pipeline.to_s} do
      #{pipes[1]}
      #{plug}
      end
    PLUGS
    File.write("./config/routes.cr", routes.gsub(pipes[0], replacement))
  end

  def add_dependencies(dependencies)
    application = File.read("./config/application.cr")
    return if application.includes? dependencies

    replacement = <<-REQUIRES
    require "amber"
    #{dependencies}
    REQUIRES
    File.write("./config/application.cr", application.gsub("require \"amber\"", replacement))
  end

  private def fetch_database
    database = "pg"
    if File.exists?(AMBER_YML) && (yaml = YAML.parse(File.read AMBER_YML))
      database = yaml["database"].to_s if yaml["database"]?
    end
    return database
  end

  private def fetch_language
    language = "slang"
    if File.exists?(AMBER_YML) && (yaml = YAML.parse(File.read AMBER_YML))
      language = yaml["language"].to_s if yaml["language"]?
    end
    return language
  end

end

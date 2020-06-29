module Amber::CLI::Helpers
  def add_routes(pipeline, route)
    routes_file = File.read("./config/routes.cr")
    routes = routes_file.match(/routes :#{pipeline}(.*?) do(.+?)end/m)
    if routes
      replacement = <<-ROUTES
        routes :#{pipeline}#{routes[1]} do
          #{routes[2]}
          #{route}
        end
      ROUTES
      File.write("./config/routes.cr", routes_file.gsub(routes[0], replacement))
    else
      web_routes = routes_file.match(/routes :web(.*?) do(.+?)end/m)
      if web_routes
        replacement = <<-PLUGS
        routes :web#{web_routes[1]} do
          #{web_routes[2]}
        end

        routes :#{pipeline} do
          #{route}
        end
        PLUGS
        File.write("./config/routes.cr", routes_file.gsub(web_routes[0], replacement))
      end
    end
    system("crystal tool format ./config/routes.cr")
  end

  def add_plugs(pipeline, plug)
    routes_file = File.read("./config/routes.cr")
    return if routes_file.includes? plug

    pipes = routes_file.match(/pipeline :#{pipeline}(.*?) do(.+?)end/m)
    if pipes
      replacement = <<-PLUGS
      pipeline :#{pipeline}#{pipes[1]} do
        #{pipes[2]}
        #{plug}
      end
      PLUGS
      File.write("./config/routes.cr", routes_file.gsub(pipes[0], replacement))
    else
      web_pipes = routes_file.match(/pipeline :web(.*?) do(.+?)end/m)
      if web_pipes
        replacement = <<-PLUGS
        pipeline :web#{web_pipes[1]} do
          #{web_pipes[2]}
        end

        pipeline :#{pipeline} do
          #{plug}
        end
        PLUGS
        File.write("./config/routes.cr", routes_file.gsub(web_pipes[0], replacement))
      end
    end

    system("crystal tool format ./config/routes.cr")
  end

  def add_dependencies(dependencies)
    app_file_path = "./config/application.cr"
    injection_marker = "# Start Generator Dependencies: Don't modify."
    application = File.read(app_file_path)
    deps = dependencies.split("\n").reject { |d| application.includes?(d) }

    replacement = <<-REQUIRES
    #{injection_marker}
    #{deps.join("\n")}
    REQUIRES

    File.write(app_file_path, application.gsub(injection_marker, replacement)) if deps.size > 0
  end

  def self.run(command, wait = true, shell = true)
    if wait
      Process.run(command, shell: shell, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    else
      Process.new(command, shell: shell, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    end
  rescue ex : IO::Error
    # typically means we could not find the executable
    ex
  end
end

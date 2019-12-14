module Amber::CLI::Helpers
  def add_routes(pipeline, route)
    routes = File.read("./config/routes.cr")
    replacement = <<-ROUTES
    routes :#{pipeline.to_s} do
    #{route}
    ROUTES
    File.write("./config/routes.cr", routes.gsub("routes :#{pipeline.to_s} do", replacement))
    system("crystal tool format ./config/routes.cr")
  end

  def add_plugs(pipeline, plug)
    routes = File.read("./config/routes.cr")
    return if routes.includes? plug

    pipes = routes.match(/pipeline :#{pipeline.to_s} do(.+?)end/m)
    if pipes
      replacement = <<-PLUGS
      pipeline :#{pipeline.to_s} do#{pipes[1]}#{plug}
        end
      PLUGS
      File.write("./config/routes.cr", routes.gsub(pipes[0], replacement))
    else
      web_pipes = routes.match(/pipeline :web do(.+?)end/m)
      if web_pipes
        replacement = <<-PLUGS
        pipeline :web do#{web_pipes[1]}
        end

        pipeline :#{pipeline.to_s} do
          #{plug}
        end

        routes :#{pipeline.to_s} do
        end
        PLUGS
        File.write("./config/routes.cr", routes.gsub(web_pipes[0], replacement))
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
  rescue ex : Errno
    # typically means we could not find the executable
    ex
  end
end

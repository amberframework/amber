module Amber::CLI::Helpers
  def add_routes(pipeline, route)
    routes = File.read("./config/routes.cr")
    if pipeline.to_s == ":web"
      replacement = <<-ROUTES
      routes :web do
      #{route}
      ROUTES
      File.write("./config/routes.cr", routes.gsub("routes :web do", replacement))
    else
      replacement = <<-ROUTES
      routes :api, "/api" do
      #{route}
      ROUTES
      File.write("./config/routes.cr", routes.gsub("routes :api, \"/api\" do", replacement))
    end
    system("crystal tool format ./config/routes.cr")
  end

  def add_plugs(pipeline, plug)
    routes = File.read("./config/routes.cr")
    return if routes.includes? plug

    pipes = routes.match(/pipeline :#{pipeline.to_s} do(.+?)end/m)
    return unless pipes

    replacement = <<-PLUGS
    pipeline :#{pipeline.to_s} do#{pipes[1]}#{plug}
      end
    PLUGS
    File.write("./config/routes.cr", routes.gsub(pipes[0], replacement))
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

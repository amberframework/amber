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

  # HACK: Fixes race-condition on migration filenames caused by duplicated timestamps.
  # This helper method verifies filename before render it.
  # If migration file exists, then timestamp is updated.
  def verify_sql_migration_file(entry)
    if entry.is_a?(Teeplate::StringData) &&
       entry.path.ends_with?(".sql") &&
       File.exists?(File.join(Dir.current, entry.path))
      sleep 1.millisecond
      timestamp = Time.now.to_s("%Y%m%d%H%M%S%L")
      path = entry.path.sub(/\d+/, timestamp)
      new_entry = Teeplate::StringData.new(path, entry.string, entry.perm, entry.forces?)
      verify_sql_migration_file(new_entry)
    else
      entry
    end
  end

  def self.run(command, wait = true, shell = true)
    if wait
      Process.run(command, shell: shell, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    else
      Process.new(command, shell: shell, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    end
  end
end

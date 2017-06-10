Amber::Server.instance.config do |app|
  # Server options
  app_path = __FILE__ # Do not change unless you understand what you are doing.
  ENV["PORT"] ||= "4000"
  ENV["AMBER_ENV"] ||= "development"

  app.name = "Blog web application."
  app.port = ENV["PORT"].to_i
  app.env = ENV.["AMBER_ENV"].colorize(:yellow).to_s
  app.log = ::Logger.new(STDOUT)
  app.log.level = ::Logger::INFO
end

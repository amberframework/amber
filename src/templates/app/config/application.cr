Amber::Server.instance.config do |app|
  # Server options
  app_path = __FILE__          # Do not change unless you understand what you are doing.
  app.name = "#{@name.capitalize} web application."
  app.port = 3000              # Port you wish your app to run
  app.env = "development".colorize(:yellow).to_s
  app.log = ::Logger.new(STDOUT)
  app.log.level = ::Logger::INFO
end

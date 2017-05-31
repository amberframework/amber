Amber::Server.instance.config do |app|
  # Server options
  app_path = __FILE__ # Do not change unless you understand what you are doing.
  app.name = "Test_app web application."

  case AMBER_ENV
  when "production"
    app.port = 80 # Port you wish your app to run
    app.env = "production".colorize(:yellow).to_s
  when "development"
    app.port = 3000 # Port you wish your app to run
    app.env = "development".colorize(:yellow).to_s
  else
    app.port = 4000 # Port you wish your app to run
    app.env = "development".colorize(:yellow).to_s
  end

  app.log = ::Logger.new(STDOUT)
  app.log.level = ::Logger::INFO
end

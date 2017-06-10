require "sidekiq/cli"
require "amber"
require "./controllers/**"
require "./jobs/**"
require "./mailers/**"
require "./models/**"
require "./views/**"
require "../config/*"

cli = Sidekiq::CLI.new
server = cli.configure do |config|
  # middleware would be added here
end

cli.run(server)

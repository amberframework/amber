require "sidekiq/cli"
require "kemalyst"
require "../config/*"
require "./jobs/**"

cli = Sidekiq::CLI.new
server = cli.configure do |config|
  # middleware would be added here
end

cli.run(server)


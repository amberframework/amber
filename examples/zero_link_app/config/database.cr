require "amber"
require "grant"
require "grant/adapter/pg"

Grant::Connections << Grant::Adapter::Pg.new(
  name: "primary",
  url: ENV["DATABASE_URL"]? || Amber.settings.database_url
)

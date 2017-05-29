require "sidekiq"
require "../src/jobs/**"

Sidekiq::Client.default_context = Sidekiq::Client::Context.new

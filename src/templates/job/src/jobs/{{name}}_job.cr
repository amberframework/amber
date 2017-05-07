require "sidekiq"

class <%= @name.capitalize %>Job
  include Sidekiq::Worker

  def perform(<%= @fields.map{|f| "#{f.name} : #{f.cr_type}"}.join(",") %>)
  end
end


require "./api_controller"

module Amber::CLI
  class ApiClearController < Amber::CLI::ApiController
    directory "#{__DIR__}/../templates/api/controller/clear"
  end
end

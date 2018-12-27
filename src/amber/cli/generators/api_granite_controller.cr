require "./api_controller"

module Amber::CLI
  class ApiGraniteController < Amber::CLI::ApiController
    directory "#{__DIR__}/../templates/api/controller/granite"
  end
end

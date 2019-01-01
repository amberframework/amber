require "./api_controller"

module Amber::CLI
  class ApiCrectoController < Amber::CLI::ApiController
    directory "#{__DIR__}/../templates/api/controller/crecto"
  end
end

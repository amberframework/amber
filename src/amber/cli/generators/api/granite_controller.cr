require "./controller"

module Amber::CLI::Api
  class GraniteController < Amber::CLI::Api::Controller
    directory "#{__DIR__}/../../templates/api/controller/granite"
  end
end

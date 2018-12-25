require "./controller"

module Amber::CLI::Api
  class CrectoController < Amber::CLI::Api::Controller
    directory "#{__DIR__}/../../templates/api/controller/crecto"
  end
end

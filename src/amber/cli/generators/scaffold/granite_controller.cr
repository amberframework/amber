require "./controller"

module Amber::CLI::Scaffold
  class GraniteController < Amber::CLI::Scaffold::Controller
    directory "#{__DIR__}/../../templates/scaffold/controller/granite"
  end
end

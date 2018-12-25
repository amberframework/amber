require "./controller"

module Amber::CLI::Scaffold
  class CrectoController < Amber::CLI::Scaffold::Controller
    directory "#{__DIR__}/../../templates/scaffold/controller/crecto"
  end
end

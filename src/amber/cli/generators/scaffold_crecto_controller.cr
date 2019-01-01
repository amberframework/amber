require "./scaffold_controller"

module Amber::CLI
  class ScaffoldCrectoController < Amber::CLI::ScaffoldController
    directory "#{__DIR__}/../templates/scaffold/controller/crecto"
  end
end

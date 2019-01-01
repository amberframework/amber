require "./scaffold_controller"

module Amber::CLI
  class ScaffoldGraniteController < Amber::CLI::ScaffoldController
    directory "#{__DIR__}/../templates/scaffold/controller/granite"
  end
end

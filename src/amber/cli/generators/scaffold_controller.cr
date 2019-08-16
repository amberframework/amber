module Amber::CLI
  class ScaffoldController < Amber::CLI::Generator
    directory "#{__DIR__}/../templates/scaffold/controller"

    def initialize(name, fields)
      super(name, fields)
      add_timestamp_fields
    end

    def pre_render(directory, **args)
      add_routes
    end

    private def add_routes
      add_routes :web, <<-ROUTE
        resources "#{name_plural}", #{class_name}Controller
      ROUTE
    end
  end
end

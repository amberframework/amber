module Amber::CLI
  class ScaffoldView < Amber::CLI::Generator
    directory "#{__DIR__}/../templates/scaffold/view"

    def initialize(name, fields)
      super(name, fields)
      add_timestamp_fields
    end
  end
end

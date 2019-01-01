require "./field.cr"

module Amber::CLI
  class Mailer < Generator
    directory "#{__DIR__}/../templates/mailer"

    def initialize(name, fields)
      super(name, fields)
    end

    def pre_render(directory)
      add_dependencies
    end

    private def add_dependencies
      add_dependencies <<-DEPENDENCY
      require "../src/mailers/**"
      DEPENDENCY
    end
  end
end

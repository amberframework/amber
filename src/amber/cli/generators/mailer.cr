require "./field.cr"

module Amber::CLI
  class Mailer < Generator
    command :mailer
    directory "#{__DIR__}/../templates/mailer"

    def initialize(name, fields)
      super(name, fields)
    end
  end
end

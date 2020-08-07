module Amber::CLI
  class Migration < Generator
    directory "#{__DIR__}/../templates/migration/full"

    def initialize(name, fields)
      super(name, fields)
      add_timestamp_fields
    end
  end
end

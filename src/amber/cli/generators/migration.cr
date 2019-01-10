module Amber::CLI
  class Migration < Generator
    command :migration
    directory "#{__DIR__}/../templates/migration/empty"

    def initialize(name, fields)
      super(name, fields)
      add_timestamp_fields
    end
  end
end

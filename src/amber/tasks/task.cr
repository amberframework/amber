module Amber::Tasks
  abstract class Task
    macro inherited
      Amber::Tasks::Runner.tasks << self.new
    end

    abstract def description
    abstract def perform
  end

  class NullTask
    def description
      "No Description"
    end

    def perform
      nil
    end
  end
end

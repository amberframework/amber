module Amber::Tasks
  class Runner
    class_property tasks = [] of Amber::Tasks::Task
    getter task : String

    def self.perform(task)
      new(task).perform
    end

    def self.definitions
      String.build do |str|
        tasks.each do |task|
          str << task.class.name
          str << "\t\t #"
          str << task.description
          str << "\n"
        end
      end
    end

    def initialize(@task : String)
    end

    def tasks
      self.class.tasks
    end

    def perform
      find(task).perform
    end

    private def find(lookup_task)
      self.class.tasks.find(Amber::Tasks::NullTask.new) do |task|
        task.class.name.downcase == lookup_task.downcase
      end
    end
  end
end

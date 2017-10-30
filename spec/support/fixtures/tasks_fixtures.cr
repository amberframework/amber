class FakeTask < Amber::Tasks::Task
  def description
    "Fake command task"
  end

  def perform
    "Fake task completed!"
  end
end

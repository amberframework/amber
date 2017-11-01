class FakeTask < Amber::Tasks::Task
  def description
    "Fake command task"
  end

  def perform
    "Fake task completed!"
  end
end

def expected_tasks_output
  <<-OUTPUT
  FirstFakeTask\t\t #First fake task
  Second::FakeTask\t\t #Second fake task
  FakeTask\t\t #Fake command task

  OUTPUT
end

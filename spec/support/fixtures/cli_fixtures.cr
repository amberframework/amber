module CLIFixtures
  def expected_controller
    <<-CONT
class AnimalController < ApplicationController
  def add
    render("add.slang")
  end

  def list
    render("list.slang")
  end

  def remove
    render("remove.slang")
  end
end

CONT
  end
end

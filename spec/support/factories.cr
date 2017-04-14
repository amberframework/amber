require "../../src/amber/*"

class HelloController < Amber::Controller
  def index; end

  def world
    "Hello World!"
  end
end

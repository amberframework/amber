require "../../src/amber/*"
require "../../src/amber/**"

class HelloController < Amber::Controller::Base
  def index; end

  def world
    "Hello World!"
  end
end

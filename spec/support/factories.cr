require "../../src/amber/*"
require "../../src/amber/**"

class HelloController < Amber::Controller::Base

  before_action do
    only [:index] { say_hello }
  end

  after_action do
    only [:index] { say_something }
  end


  def index; end

  def world
    "Hello World!"
  end

  def say_hello
    "Hello Amber!"
  end

  def say_something(say)
    puts say
  end

end

class TestController < Amber::Controller::Base
  def render_template_page
    render_template("spec/sample/views/test.slang")
  end

  def render_layout_too
    render_both("spec/sample/views/test.slang", "spec/sample/views/layout.slang")
  end

  def render_both_inferred
    render("test.slang", "layout.slang", "spec/sample/views", "./")
  end
end

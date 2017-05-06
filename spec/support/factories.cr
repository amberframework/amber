require "../../src/amber/*"
require "../../src/amber/**"

class HelloController < Amber::Controller::Base
  @total : Int32 = 0

  before_action do
    only [:index, :world, :show] { increment(3) }
    only :index { increment(1) }
    all { say_hello }
  end

  after_action do
    only [:index, :world] { increment(2) }
  end

  def index; end

  def world
    "Hello World!"
  end

  def say_hello
    "Hello Amber!"
  end

  def increment(n)
    @total = @total + n
  end

  def total
    @total
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

struct UserSocket < Amber::WebSockets::ClientSocket
  channel "user_room:*", UserChannel
end

class UserChannel < Amber::WebSockets::Channel
  def handle_joined; end

  def handle_message(msg); end
end

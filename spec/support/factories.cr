require "../../src/amber/*"
require "../../src/amber/**"

class HelloController < Amber::Controller::Base
  def index; end

  def world
    "Hello World!"
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
  channel "user_room/*", UserChannel
end

class UserChannel < Amber::WebSockets::Channel
  def joined;end
end

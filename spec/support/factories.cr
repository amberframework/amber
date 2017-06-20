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

  def index
    "Index"
  end

  def show
    "Show"
  end

  def new
    "New"
  end

  def edit
    "Edit"
  end

  def update
    "Update"
  end

  def create
    "Create"
  end

  def destroy
    "Destroy"
  end

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
    render("spec/sample/views/test/test.slang", layout: false)
  end

  def render_partial
    render("spec/sample/views/test/_test.slang")
  end

  def render_with_layout
    render("test/test.slang", "layout.slang", "spec/sample/views", "./")
  end

  def render_with_csrf
    render("spec/sample/views/test/_form.slang", layout: false)
  end
end

struct UserSocket < Amber::WebSockets::ClientSocket
  channel "user_room:*", UserChannel
end

class UserChannel < Amber::WebSockets::Channel
  property test_field = Array(String).new

  def handle_leave(client_socket)
    test_field.push("handle leave #{client_socket.id}")
  end

  def handle_joined(client_socket)
    test_field.push("handle joined #{client_socket.id}")
  end

  def handle_message(msg)
    test_field.push(msg["payload"]["message"].as_s)
  end
end

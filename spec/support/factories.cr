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
    render("spec/support/sample/views/test/test.slang", layout: false)
  end

  def render_partial
    render(partial: "spec/support/sample/views/test/_test.slang")
  end

  def render_with_layout
    render("test/test.slang", layout: "layout.slang", path: "spec/support/sample/views", folder: "./")
  end

  def render_multiple_partials_in_layout
    render("test/test.slang", layout: "layout_with_partials.slang", path: "spec/support/sample/views", folder: "./")
  end

  def render_with_csrf
    render(partial: "spec/support/sample/views/test/_form.slang")
  end

  def render_with_flash
    flash["error"] = "Displays error Message!"
    render("spec/support/sample/views/test/flash.slang", layout: false)
  end
end

struct UserSocket < Amber::WebSockets::ClientSocket
  property test_field = Array(String).new

  channel "user_room:*", UserChannel

  def on_disconnect(**args)
    test_field.push("on close #{self.id}")
  end
end

class UserChannel < Amber::WebSockets::Channel
  property test_field = Array(String).new

  def handle_leave(client_socket)
    test_field.push("handle leave #{client_socket.id}")
  end

  def handle_joined(client_socket, msg)
    test_field.push("handle joined #{client_socket.id}")
  end

  def handle_message(client_socket, msg)
    test_field.push(msg["payload"]["message"].as_s)
  end
end

class RedirectController < Amber::Controller::Base
  def index
    "Index"
  end

  def show
    "Show"
  end

  def edit
    "Edit"
  end

  def update
    "Update"
  end

  def destroy
    "Destroy"
  end
end

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

  def client_ip_address
    client_ip.not_nil!.address
  end

  def increment(n)
    @total = @total + n
  end

  def total
    @total
  end
end

class RenderController < Amber::Controller::Base
  def render_template_page
    render(path: "spec/support/sample/views", template: "test/test.slang", layout: false)
  end

  def render_partial
    render(path: "spec/support/sample/views", partial: "test/_test.slang")
  end

  def render_with_layout
    render("test/test.slang", layout: "layout.slang", path: "spec/support/sample/views", folder: "./")
  end

  def render_multiple_partials_in_layout
    render("test/test.slang", layout: "layout_with_partials.slang", path: "spec/support/sample/views", folder: "./")
  end

  def render_with_csrf
    render(path: "spec/support/sample/views", partial: "test/_form.slang")
  end

  def render_with_flash
    flash["error"] = "Displays error Message!"
    render(path: "spec/support/sample/views", template: "test/flash.slang", layout: false)
  end
end

class ResponsesController < Amber::Controller::Base
  def index
    respond_with do
      html "<html><body><h1>Elorest <3 Amber</h1></body></html>"
      json type: "json", name: "Amberator"
      xml "<xml><body><h1>Sort of xml</h1></body></xml>"
      text "Hello I'm text!"
    end
  end

  def show
    respond_with do
      html "<html><body><h1>Elorest <3 Amber</h1></body></html>"
      json type: "json", name: "Amberator"
    end
  end

  def custom_status_code
    respond_with(403) do
      json type: "json", error: "Unauthorized"
    end
  end
end

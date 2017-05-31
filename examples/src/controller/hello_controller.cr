class HelloController < Amber::Controller::Base
  @num = 0

  # Filters are methods that are run "before", "after" a controller action.
  before_action do
    only [:index, :world, :show] { increment(1) }
    only :index { increment(1) }
  end

  after_action do
    only [:index, :world] { increment(1) }
  end

  def hello_world
    "Hello World! Running filters? #{@num}"
  end

  def index
    "Hello from no where, Increment result: #{@num}"
  end

  def edit
    "Edit Action"
  end

  def new
    "New Action"
  end

  def show
    "Show Action"
  end

  def create
    "Create Action"
  end

  def update
    "Update Action"
  end

  def destroy
    "Delete Action"
  end

  def world
    if params.valid?
      "Welcome to planet: #{params["planet"]}!"
    else
      "There is no world defined!"
    end
  end

  def template
    render "hello.slang"
  end

  def increment(n)
    @num += n
  end

  def hello_params
    params.validation do
      required(:planet) { |w| !w.empty? }
    end
  end
end

module ControllerHelper
  def build_controller(referer = "")
    request = HTTP::Request.new("GET", "/")
    request.headers.add("Referer", referer)
    context = create_context(request)
    HelloController.new(context)
  end

  def assert_expected_response?(controller, location, status_code)
    controller.response.headers["location"].should eq location
    controller.response.status_code.should eq status_code
  end

  def setup_routes
    pipeline = Launch::Pipe::Pipeline.new

    Launch::Server.router.draw :web do
      get "/valid/route", HelloController, :world
      get "/index/:name", HelloController, :world
      resources "/hello", HelloController
    end

    pipeline.build :web { }
    pipeline.prepare_pipelines
    pipeline
  end
end

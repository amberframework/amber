module ControllerHelper
  def build_controller(referer = "")
    request = HTTP::Request.new("GET", "/")
    request.headers.add("Referer", referer)
    context = create_context(request)
    HelloController.new(context)
  end
end

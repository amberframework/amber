require "./probe_support"

class APICardControllerHelpers
  include Amber::Testing::ControllerHelpers

  def context : HTTP::Server::Context
    build_test_context(params: {"name" => "Ada"})
  end
end

helper = APICardControllerHelpers.new
typeof(helper.context).should eq(HTTP::Server::Context)
typeof(Amber::Testing::ContextBuilder.new.path("/items").build).should eq(HTTP::Server::Context)

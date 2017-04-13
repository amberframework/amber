require "./../spec_helper"

class HelloController
    def world; end
    def index; end
end

describe Amber::Router do
    it "parses the controller correctly" do
        router = Amber::Router.new
        get("/", "hello#world").should eq Proc
    end
end

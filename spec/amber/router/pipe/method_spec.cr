require "../../../../spec_helper"

module Amber
  module Pipe
    describe Method do
      describe "#request_method_override!" do

        describe "when X-HTTP-Method-Overrid is present" do
          it "overrides form POST method to PUT, PATCH, DELETE" do
            %w(PUT PATCH DELETE).each do |method|
              header = HTTP::Headers.new
              header[Method::OVERRIDE_HEADER] = method
              request = HTTP::Request.new("POST", "/?test=test", header)
              context = create_context(request)

              Method.new.call(context)

              context.request.method.should eq method
            end
          end

          it "overrides form GET method to PUT, PATCH, DELETE" do
            %w(PUT PATCH DELETE).each do |method|
              header = HTTP::Headers.new
              header[Method::OVERRIDE_HEADER] = method
              request = HTTP::Request.new("GET", "/?test=test", header)
              context = create_context(request)

              Method.new.call(context)

              context.request.method.should eq method
            end
          end

          it "takes form post over header override" do
            %w(PUT PATCH DELETE).each do |method|
              header = HTTP::Headers.new
              header[Method::OVERRIDE_HEADER] = method
              header["content-type"] = "application/x-www-form-urlencoded"
              request = HTTP::Request.new("GET", "/?test=test", header, "_method=PATCH")
              context = create_context(request)

              Method.new.call(context)

              context.request.method.should eq "PATCH"
            end
          end
        end

        it "overrides form POST method to PUT, PATCH, DELETE" do
          %w(PUT PATCH DELETE).each do |method|
            header = HTTP::Headers.new
            header["content-type"] = "application/x-www-form-urlencoded"
            request = HTTP::Request.new("POST", "/?test=test", header, "_method=#{method}")
            context = create_context(request)

            Method.new.call(context)

            context.request.method.should eq method
          end
        end

        it "overrides form GET method to PUT, PATCH, DELETE" do
          %w(PUT PATCH DELETE).each do |method|
            header = HTTP::Headers.new
            header["content-type"] = "application/x-www-form-urlencoded"
            request = HTTP::Request.new("GET", "/?test=test", header, "_method=#{method}")
            context = create_context(request)

            Method.new.call(context)

            context.request.method.should eq method
          end
        end

        it "does not override other than PUT, PATCH, DELETE" do
          %w(PUT PATCH DELETE).each do |method|
            header = HTTP::Headers.new
            header["content-type"] = "application/x-www-form-urlencoded"
            request = HTTP::Request.new("HEAD", "/?test=test", header, "_method=#{method}")
            context = create_context(request)

            Method.new.call(context)

            context.request.method.should eq "HEAD"
          end
        end
      end
    end
  end
end

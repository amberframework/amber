require "../../../../spec_helper"

module Amber
  module Pipe
    describe CSRF do
      context "when requests have HTTP methods" do
        CSRF::CHECK_METHODS.each do |method|
          it "raises forbidden error for #{method} request" do
            csrf = CSRF.new

            request = HTTP::Request.new(method, "/")

            expect_raises Exceptions::Forbidden do
              make_router_call(csrf, request)
            end
          end
        end
      end

      context "when requests have allowed HTTP methods" do
        %w(GET HEAD OPTIONS TRACE CONNECT).each do |method|
          it "accepts requests for GET methods" do
            csrf = CSRF.new
            request = HTTP::Request.new(method, "/")

            response = make_router_call(csrf, request)

            response.should be_nil
          end
        end
      end

      context "when tokens match" do
        it "accepts requests params token" do
          csrf = CSRF.new
          request = HTTP::Request.new("PUT", "/")
          context = create_context(request)
          token = CSRF.token(context)
          context.params[Amber::Pipe::CSRF::PARAM_KEY] = token.to_s

          result = csrf.call(context)

          result.should be_nil
        end

        it "accepts requests for header token" do
          csrf = CSRF.new
          request = HTTP::Request.new("PUT", "/")
          context = create_context(request)
          token = CSRF.token(context)
          context.request.headers[Amber::Pipe::CSRF::HEADER_KEY] = token.to_s

          result = csrf.call(context)

          result.should be_nil
        end
      end

      context "across requests" do
        it "is valid across request" do
          csrf = CSRF.new
          request = HTTP::Request.new("GET", "/")
          context = create_context(request)

          token = CSRF.token(context)
          Session.new.call(context)

          context.response.headers["content-type"] = "application/x-www-form-urlencoded"

          request2 = HTTP::Request.new("post", "/?_csrf=#{token}", context.response.headers)
          context2 = create_context(request2)

          context2.params["_csrf"].should eq token
          context2.session["csrf.token"].should eq token
          CSRF.new.valid_token?(context2).should eq true
        end
      end

      context "when tokens don't match" do
        it "raises a forbbiden error for params token" do
          csrf = CSRF.new
          request = HTTP::Request.new("PUT", "/")
          context = create_context(request)

          context.session["csrf.token"] = "good_token"
          context.params["_csrf"] = "different_token"

          expect_raises Exceptions::Forbidden do
            csrf.call(context)
          end
        end

        it "raises a forbbiden error for header token" do
          csrf = CSRF.new
          request = HTTP::Request.new("PUT", "/")
          context = create_context(request)

          context.session["csrf.token"] = "good_token"
          context.request.headers["HTTP_X_CSRF_TOKEN"] = "different_token"

          expect_raises Exceptions::Forbidden do
            csrf.call(context)
          end
        end
      end
    end
  end
end

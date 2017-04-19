require "../../../spec_helper"

module Amber
  module Pipe
    describe CSRF do

      context "when requests have HTTP methods" do
        CSRF::CHECK_METHODS.each do |method|
          it "raises forbbiden error for PUT request" do
            csrf = CSRF.instance
            request = HTTP::Request.new(method, "/")

            expect_raises Amber::Exceptions::Forbidden do
              make_router_call(csrf, request)
            end
          end
        end
      end

      context "when requests have allowed HTTP methods" do
        %w(GET HEAD OPTIONS TRACE CONNECT).each do |method|
          it "accepts requests for GET methods" do
            csrf = CSRF.instance
            request = HTTP::Request.new(method, "/")

            response = make_router_call(csrf, request)

            response.should be_nil
          end
        end
      end

      context "when tokens match" do
        it "accepts requests params token" do
          csrf = CSRF.instance
          valid_token = "good_token"
          request = HTTP::Request.new("PUT", "/")
          context = create_context(request)

          context.session["csrf.token"] = valid_token
          context.params["_csrf"] = valid_token

          result = csrf.call(context)

          result.should be_nil
        end

        it "accepts requests for header token" do
          csrf = CSRF.instance
          valid_token = "good_token"
          request = HTTP::Request.new("PUT", "/")
          context = create_context(request)

          context.session["csrf.token"] = valid_token
          context.request.headers["HTTP_X_CSRF_TOKEN"] = valid_token

          result = csrf.call(context)

          result.should be_nil
        end
      end

      context "when tokens don't match" do
        it "raises a forbbiden error for params token" do
          csrf = CSRF.instance
          request = HTTP::Request.new("PUT", "/")
          context = create_context(request)

          context.session["csrf.token"] = "good_token"
          context.params["_csrf"] = "different_token"

          expect_raises Exceptions::Forbidden do
            csrf.call(context)
          end
        end

        it "raises a forbbiden error for header token" do
          csrf = CSRF.instance
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
require "../../../../spec_helper"

module Amber
  module Pipe
    describe CSRF do
      Dir.cd CURRENT_DIR
      Amber.env = :test

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
          request = HTTP::Request.new("GET", "/")
          context = create_context(request)

          token = CSRF.token(context)
          Session.new.call(context)

          request2 = HTTP::Request.new("POST", "/?_csrf=#{token}", context.response.headers)

          context2 = create_context(request2)

          CSRF.token_strategy.valid_token?(context2).should eq true
        end
      end

      context "when tokens don't match" do
        it "raises a forbidden error for params token" do
          csrf = CSRF.new
          request = HTTP::Request.new("PUT", "/")
          context = create_context(request)

          context.session["csrf.token"] = "good_token"
          context.params["_csrf"] = "different_token"

          expect_raises Exceptions::Forbidden do
            csrf.call(context)
          end
        end

        it "raises a forbidden error for header token" do
          csrf = CSRF.new
          request = HTTP::Request.new("PUT", "/")
          context = create_context(request)

          context.session["csrf.token"] = "good_token"
          context.request.headers["HTTP_X_CSRF_TOKEN"] = "different_token"

          expect_raises Exceptions::Forbidden do
            csrf.call(context)
          end
        end

        it "raises a forbidden error for an invalid base64 token" do
          csrf = CSRF.new
          request = HTTP::Request.new("PUT", "/")
          context = create_context(request)

          context.session["csrf.token"] = "good_token"
          context.params["_csrf"] = "invalid_token"

          expect_raises Exceptions::Forbidden do
            csrf.call(context)
          end
        end
      end

      context "generator" do
        it "masks token for client" do
          request = HTTP::Request.new("GET", "/")
          context = create_context(request)

          token = CSRF.token(context)
          real_session_token = CSRF.token_strategy.real_session_token(context)

          token.should_not eq real_session_token
        end

        it "generates random tokens for client" do
          request = HTTP::Request.new("GET", "/")
          context = create_context(request)

          token1 = CSRF.token(context)
          token2 = CSRF.token(context)

          token1.should_not eq token2
        end
      end

      context "TokenOperations" do
        it "properly unmasks masked token" do
          request = HTTP::Request.new("GET", "/")
          context = create_context(request)
          decoded_token = Base64.decode(CSRF.token_strategy.real_session_token(context))

          masked = CSRF::PersistentToken::TokenOperations.mask(decoded_token)
          unmasked = CSRF::PersistentToken::TokenOperations.unmask(Base64.decode(masked))

          decoded_token.should eq unmasked
        end
      end
    end
  end
end

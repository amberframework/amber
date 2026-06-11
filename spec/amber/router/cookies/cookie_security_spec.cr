require "../../../spec_helper"

module Amber::Router
  describe "Cookie Security Improvements" do
    describe "SameSite Cookie Support" do
      it "sets a cookie with SameSite=Lax" do
        cookies = new_cookie_store

        cookies.set "user_name", "david", samesite: HTTP::Cookie::SameSite::Lax

        cookie_header(cookies).should contain("SameSite=Lax")
      end

      it "sets a cookie with SameSite=Strict" do
        cookies = new_cookie_store

        cookies.set "user_name", "david", samesite: HTTP::Cookie::SameSite::Strict

        cookie_header(cookies).should contain("SameSite=Strict")
      end

      it "sets a cookie with SameSite=None" do
        cookies = new_cookie_store

        cookies.set "user_name", "david", samesite: HTTP::Cookie::SameSite::None, secure: true
        cookies.secure = true

        cookie_header(cookies).should contain("SameSite=None")
      end

      it "does not include SameSite when nil" do
        cookies = new_cookie_store

        cookies.set "user_name", "david"

        cookie_header(cookies).should_not contain("SameSite")
      end

      it "sets SameSite on encrypted cookies" do
        cookies = new_cookie_store

        cookies.encrypted.set "secret_data", "value", samesite: HTTP::Cookie::SameSite::Lax

        cookie_header(cookies).should contain("SameSite=Lax")
      end

      it "sets SameSite on signed cookies" do
        cookies = new_cookie_store

        cookies.signed.set "signed_data", "value", samesite: HTTP::Cookie::SameSite::Strict

        cookie_header(cookies).should contain("SameSite=Strict")
      end

      it "sets SameSite on permanent cookies" do
        cookies = new_cookie_store

        cookies.permanent.set "perm_data", "value", samesite: HTTP::Cookie::SameSite::Lax

        cookie_header(cookies).should contain("SameSite=Lax")
      end
    end

    describe "Error Handling in Cookie Stores" do
      context "EncryptedStore" do
        it "returns nil for tampered cookie instead of empty string" do
          cookies = new_cookie_store
          cookie = HTTP::Cookie::Parser.parse_cookies("secret=tampered_value; path=/").first
          cookies[cookie.name] = cookie

          cookies.encrypted["secret"].should be_nil
        end

        it "returns nil for corrupted base64 in encrypted cookie" do
          cookies = new_cookie_store(HTTP::Headers{"Cookie" => "secret=not_valid_base64!!!"})

          cookies.encrypted["secret"].should be_nil
        end

        it "still returns nil for unset encrypted cookies" do
          cookies = new_cookie_store

          cookies.encrypted["nonexistent"].should be_nil
        end

        it "correctly round-trips encrypted values" do
          cookies = new_cookie_store
          cookies.encrypted.set "key", "my secret value"

          cookies.encrypted["key"].should eq("my secret value")
        end
      end

      context "SignedStore" do
        it "returns nil for tampered signed cookie instead of empty string" do
          cookies = new_cookie_store
          cookie = HTTP::Cookie::Parser.parse_cookies("signed=tampered--invalid_sig; path=/").first
          cookies[cookie.name] = cookie

          cookies.signed["signed"].should be_nil
        end

        it "returns nil for cookie without separator" do
          cookies = new_cookie_store
          cookie = HTTP::Cookie::Parser.parse_cookies("signed=no_separator_here; path=/").first
          cookies[cookie.name] = cookie

          cookies.signed["signed"].should be_nil
        end

        it "still returns nil for unset signed cookies" do
          cookies = new_cookie_store

          cookies.signed["nonexistent"].should be_nil
        end

        it "correctly round-trips signed values" do
          cookies = new_cookie_store
          cookies.signed.set "key", "my signed value"

          cookies.signed["key"].should eq("my signed value")
        end
      end
    end
  end
end

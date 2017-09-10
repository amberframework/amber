require "../../../spec_helper"

module Amber::Router
  describe Cookies::Store do
    it "sets a cookie" do
      cookies = new_cookie_store

      cookies.set "user_name", "david"

      cookie_header(cookies).should eq "user_name=david; path=/"
    end

    it "reads a cookie" do
      cookies = new_cookie_store

      cookies.set "user_name", "Jamie"

      cookies["user_name"].should eq "Jamie"
    end

    it "sets a permanent cookie" do
      cookies = new_cookie_store

      cookies.set "user_name", "Jamie"

      cookies.permanent.set "user_name", "Jamie"
      cookie_header(cookies).should eq "user_name=Jamie; path=/; expires=#{HTTP.rfc1123_date(20.years.from_now)}"
    end

    it "reads a permanent cookie" do
      cookies = new_cookie_store

      cookies.permanent.set "user_name", "Jamie"

      cookies.permanent["user_name"].should eq "Jamie"
    end

    it "sets a cookie with escapable characters" do
      cookies = new_cookie_store

      cookies.set "that & guy", "foo & bar => baz"

      cookie_header(cookies).should eq "that%20%26%20guy=foo%20%26%20bar%20%3D%3E%20baz; path=/"
    end

    it "sets the cookie with expiration" do
      cookies = new_cookie_store

      cookies.set "user_name", "david", expires: Time.new(2017, 6, 7, 9)

      cookie_header(cookies).should eq "user_name=david; path=/; expires=#{HTTP.rfc1123_date(Time.new(2017, 6, 7, 9))}"
    end

    it "sets the cookie with http_only" do
      cookies = new_cookie_store

      cookies.set "user_name", "david", http_only: true

      cookie_header(cookies).should eq "user_name=david; path=/; HttpOnly"
    end

    it "sets the cookie with secure if the jar is secure" do
      cookies = new_cookie_store
      cookies.secure = true

      cookies.set "user_name", "david", secure: true

      cookie_header(cookies).should eq "user_name=david; path=/; Secure"
    end

    it "does not set the cookie with secure if the jar is insecure" do
      cookies = new_cookie_store
      cookies.secure = false

      cookies.set "user_name", "david", secure: true

      cookie_header(cookies).should eq ""
    end

    it "sets the insecure cookie with if the jar is secure" do
      cookies = new_cookie_store
      cookies.secure = true

      cookies.set "user_name", "david", secure: false

      cookie_header(cookies).should eq "user_name=david; path=/"
    end

    it "sets multiple cookies" do
      cookies = new_cookie_store

      cookies.set "user_name", "david", expires: Time.new(2017, 6, 7, 9)
      cookies.set "login", "XJ-122"

      cookies.size.should eq 2
      cookie_header(cookies).should eq "user_name=david; path=/; expires=#{HTTP.rfc1123_date(Time.new(2017, 6, 7, 9))},login=XJ-122; path=/"
    end

    context "encrypted cookies" do
      it "sets an encrypted cookie" do
        cookies = new_cookie_store
        cookies.encrypted.set "user_name", "david"

        cookie_header(cookies).should_not eq "user_name=david; path=/"
      end

      it "gets an encrypted cookie" do
        cookies = new_cookie_store
        cookies.encrypted.set "user_name", "david"

        cookies.encrypted["user_name"].should eq "david"
      end

      it "ignores tampered cookie signature" do
        cookies = new_cookie_store
        cookie = HTTP::Cookie::Parser.parse_cookies("user_name=LByguEoiSsJqc1iG%2FPrIujkr5ha0yUi%2Fng2fT4XSX3I%3D--tampered; path=/").first

        cookies[cookie.name] = cookie

        cookies.encrypted["user_name"].should eq ""
      end

      it "ignores tampered cookie value" do
        cookies = new_cookie_store(HTTP::Headers{"Cookie" => "user_name=tampered%3D%3D--cead74d6b7a64512a499fef31483fd21d9e89b85378a3eaa440c7ac7f9cd6b94;"})

        cookies.encrypted["user_name"].should eq ""
      end

      it "ignores unset encrypted cookies" do
        cookies = new_cookie_store

        cookies.encrypted["invalid"].should eq nil
      end
    end

    context "signed cookies" do
      it "sets a cookie" do
        cookies = new_cookie_store
        cookies.signed.set "user_name", "david"

        cookie_header(cookies).should_not eq "user_name=david; path=/"
      end

      it "gets a cookie" do
        cookies = new_cookie_store
        cookies.signed.set "user_name", "david"

        cookies.signed["user_name"].should eq "david"
      end

      it "ignores tampered cookie signature" do
        cookies = new_cookie_store
        cookie = HTTP::Cookie::Parser.parse_cookies("user_name=ZGF2aWQ%3D--tampered; path=/").first

        cookies[cookie.name] = cookie

        cookies.signed["user_name"].should eq ""
      end

      it "ignores tampered cookie value" do
        cookies = new_cookie_store(HTTP::Headers{"Cookie" => "user_name=tampered%3D%3D--cead74d6b7a64512a499fef31483fd21d9e89b85378a3eaa440c7ac7f9cd6b94;"})

        cookies.signed["user_name"].should eq ""
      end

      it "ignores cookie without signature" do
        cookies = new_cookie_store
        cookie = HTTP::Cookie::Parser.parse_cookies("user_name=ZGF2aWQ%3D; path=/").first

        cookies[cookie.name] = cookie

        cookies.signed["user_name"].should eq ""
      end

      it "ignores unset encrypted cookies" do
        cookies = new_cookie_store

        cookies.signed["invalid"].should eq nil
      end
    end

    it "raises cookie overflow error" do
      cookies = new_cookie_store

      expect_raises(Exceptions::CookieOverflow) do
        cookies.encrypted["user_name"] = "long" * 2000
      end
    end

    it "deletes a cookie" do
      cookies = new_cookie_store(HTTP::Headers{"Cookie" => "user_name=david"})

      cookies["user_name"].should eq "david"

      cookies.delete "user_name"

      cookie_header(cookies).should eq "user_name=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT"
    end

    it "allow deleting a unexisting cookie" do
      cookies = new_cookie_store

      cookies.delete "invalid"
    end

    it "returns true if the cookie is delete" do
      cookies = new_cookie_store(HTTP::Headers{"Cookie" => "user_name=david"})

      cookies.delete "user_name"

      cookies.deleted?("user_name").should eq true
    end
  end
end

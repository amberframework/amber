require "../../../spec_helper"

private def cookies_from(header : String) : Hash(String, String)
  cookies = {} of String => String
  Amber::Router::Cookies::HeaderParser.each_cookie(header) { |cookie| cookies[cookie.name] = cookie.value }
  cookies
end

describe Amber::Router::Cookies::HeaderParser do
  it "reads pairs, trims whitespace and unwraps quotes" do
    cookies_from(%(a=1; b = 2; c="three")).should eq({"a" => "1", "b" => "2", "c" => "three"})
  end

  it "keeps an equals sign inside a value" do
    cookies_from("flavor=abc==").should eq({"flavor" => "abc=="})
  end

  it "leaves out a malformed pair and keeps its neighbors" do
    cookies_from(%(good=1; noequals; bad"name=2; also=3)).should eq({"good" => "1", "also" => "3"})
  end

  it "keeps the first of two cookies joined by a bare semicolon, as request.cookies does" do
    cookies_from("session=A;session=B").should eq({"session" => "A"})
  end

  it "does not raise on a name the cookie type rejects" do
    cookies_from(%(é=1; b=2)).should eq({"b" => "2"})
  end

  it "answers no cookies for an empty header" do
    cookies_from("").should be_empty
  end

  it "agrees with the standard library on generated hostile headers" do
    list_of_pieces = ["a", "b", "session", "=", "=", ";", "; ", "; ", " ", "\t", "\"", "\\", ",", "1", "x y", "(", "é", "%3D", ""]
    random = Random.new(20261106)

    60_000.times do
      header = String.build { |text| random.rand(1..10).times { text << list_of_pieces.sample(random) } }

      expected = begin
        HTTP::Cookies.from_client_headers(HTTP::Headers{"Cookie" => header}).to_h.transform_values(&.value)
      rescue IO::Error | ArgumentError
        # The standard library raises on this header. Amber answers with the valid pairs.
        next
      end

      fail "#{header.inspect}: standard library says #{expected}, Amber says #{cookies_from(header)}" unless cookies_from(header) == expected
    end
  end

  it "agrees with the standard library on well-formed headers" do
    {"a=1", "a=1; b=2", %(a="1"; b=2), "session=abc%3D%3D; theme=dark"}.each do |header|
      standard_headers = HTTP::Headers{"Cookie" => header}
      expected = HTTP::Cookies.from_client_headers(standard_headers).to_h.transform_values(&.value)
      cookies_from(header).should eq(expected)
    end
  end
end

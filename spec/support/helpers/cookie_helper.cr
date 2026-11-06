module CookieHelper
  # The headers a browser sends next, carrying the cookies this response set.
  def browser_headers_after(response_headers : HTTP::Headers) : HTTP::Headers
    list_of_set_cookies = response_headers.get?("Set-Cookie") || [] of String
    HTTP::Headers{"Cookie" => list_of_set_cookies.map(&.partition(';').first).join("; ")}
  end

  def new_cookie_store(headers = HTTP::Headers.new)
    cookies = Amber::Router::Cookies::Store.new
    cookies.update(Amber::Router::Cookies::Store.from_headers(headers))
    cookies
  end

  def cookie_header(cookies)
    http_headers = HTTP::Headers.new
    cookies.write(http_headers)
    http_headers["Set-Cookie"]
  end
end

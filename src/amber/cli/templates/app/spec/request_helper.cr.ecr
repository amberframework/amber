require "http"

module RequestHelper
  macro included
    {% http_read_verbs = %w(get head options trace connect) %}
    {% http_write_verbs = %w(post put patch delete) %}
    {% http_verbs = http_read_verbs + http_write_verbs %}

    {% for method in http_verbs %}
      def {{method.id}}(path, headers : HTTP::Headers? = nil, body : String? = nil)
        request = HTTP::Request.new("{{method.id}}".upcase, path, headers, body )
        {% if http_write_verbs.includes? method %}
          request.headers["Content-Type"] ||= "application/x-www-form-urlencoded"
        {% end %}
        process_request(request)
      end
    {% end %}
  end

  private def process_request(request)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)
    handler.call context
    response.close
    io.rewind
    client_response = HTTP::Client::Response.from_io(io, decompress: false)
    client_response
  end
end

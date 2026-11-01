module Amber::Router::Parsers
  module FormData
    # Parse the urlencoded form WITHOUT destroying the request body.
    #
    # Reading a form is unavoidably destructive on an IO: the bytes come off the
    # socket once. But Amber parses the form for its OWN reasons — the CSRF plug
    # looks for `_csrf` in `context.params` on every state-changing request —
    # long before user code runs. The consequence was that any controller behind
    # the :web pipeline read `request.body` and got "", silently, on every form
    # POST. In production that surfaced as a public form being rejected while the
    # visitor saw nothing at all.
    #
    # The bytes are not secret and they are already in memory, so put them back.
    # Callers that reach for request.body afterwards get exactly what was sent.
    def self.parse(request : HTTP::Request)
      body = request.body
      return HTTP::Params.parse("") if body.nil?

      raw = body.gets_to_end
      request.body = IO::Memory.new(raw)
      HTTP::Params.parse(raw)
    end

    def self.parse_part(input : IO) : HTTP::Params
      HTTP::Params.parse(input.gets_to_end)
    end

    def self.parse_part(input : String) : HTTP::Params
      HTTP::Params.parse(input)
    end

    def self.parse_part(input : Nil) : HTTP::Params
      HTTP::Params.parse("")
    end
  end
end

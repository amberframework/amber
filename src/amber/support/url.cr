module Amber::Support
  module URLFor
    macro included
      def url(**options)
        URL.new(**options).to_s
      end
    end
  end

  record QueryString, query_string do
    def self.parse(query_string)
      new(query_string).to_s
    end

    @qs : String

    forward_missing_to @qs

    def initialize(query_string)
      @qs = case query_string
            when String, Nil
              HTTP::Params.parse(query_string.to_s).to_s
            when Hash(String, String)
              HTTP::Params.encode(query_string)
            when NamedTuple(key: Symbol, value: String)
              HTTP::Params.encode(query_string)
            else
              HTTP::Params.parse(query_string.to_s)
            end
    end
  end

  record URL,
    protocol : String = "http",
    host : String? = Crystal::System.hostname,
    only_path : Bool = true,
    port : Int32 = 80,
    anchor : String = "",
    query_string : String = "",
    path : String? | Symbol? = nil,
    end_slash : Bool = false do
    def to_s
      location = if only_path
                   path.to_s
                 else
                   scheme.to_s + hostname.to_s + port_number.to_s + path.to_s
                 end
      location.to_s + tail_slash.to_s + query.to_s + anchor_part.to_s
    end

    private def port_number
      if !((protocol == "http" && port == 80) || (protocol == "https" && port == 443))
        ":" + port.to_s
      end
    end

    private def query
      "?" + query_string unless query_string.empty?
    end

    private def hostname
      host
    end

    private def scheme
      "#{protocol}://"
    end

    private def anchor_part
      "##{anchor}" unless anchor.empty?
    end

    private def tail_slash
      if end_slash && (path.to_s.empty? || path.to_s.chars.last != "/")
        "/"
      end
    end
  end
end

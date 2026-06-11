module Amber::Router
  struct TerminalSegment(T)
    getter route : T
    getter full_path : String
    getter priority : Int32

    def initialize(@route, @full_path, @priority = 0)
    end

    def formatted_s(*, ts = 0)
      "#{"  " * ts}|--(#{full_path} P#{priority})\n"
    end
  end
end

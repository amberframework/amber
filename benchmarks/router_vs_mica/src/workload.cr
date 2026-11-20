require "./route_table"

module RouterVsMica
  # Checks one segment of one path against one rule, `repetitions` times,
  # through the module type the router stores rules as.
  struct RuleWorkload
    def initialize(@rule : Amber::Router::ParamConstraint, @path : String, @byte_offset : Int32,
                   @bytesize : Int32, @repetitions : Int32)
    end

    def run : Int32
      accepted = 0
      @repetitions.times do
        accepted += 1 if @rule.matches_span?(@path, @byte_offset, @bytesize)
      end
      accepted
    end
  end

  # Routes every request of a mix through one route set, `repetitions`
  # times, the way `Amber::Router::Router#match` does for a path with no
  # response extension (`RouteSet#find_span` under the verb's root).
  struct RouterWorkload
    def initialize(@route_set : Amber::Router::RouteSet(Int32), @list_of_requests : Array(RouteRequest),
                   @repetitions : Int32)
    end

    def run : Int32
      checksum = 0
      @repetitions.times do
        @list_of_requests.each do |request|
          result = @route_set.find_span(request.verb, request.path)
          checksum &+= result.payload? || -1
        end
      end
      checksum
    end
  end
end

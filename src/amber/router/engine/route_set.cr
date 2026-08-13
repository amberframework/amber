require "uri"
require "./segment_view"

module Amber::Router
  # A tree which stores and navigates routes associated with a web application.
  #
  # A route set represents the branches of the tree, and each vertex
  # is a `Segment`. Leaf nodes are `TerminalSegment`s.
  #
  # ```
  # route_set = Amber::Router::RouteSet(Symbol).new
  # route_set.add "/get/", :root
  # route_set.add "/get/users/:id", :users
  # route_set.add "/get/users/:id/books", :users_books
  # route_set.add "/get/*/slug", :slug
  # route_set.add "/get/*", :catch_all
  # route_set.add "/get/posts/:page", :pages, {"page" => /\d+/}
  #
  # route_set.formatted_s # => a textual representation of the routing tree
  #
  # route_set.find("/get/users/3").payload           # => :users
  # route_set.find("/get/users/3/books").payload     # => :users_books
  # route_set.find("/get/coffee_maker/slug").payload # => :slug
  # route_set.find("/get/made/up/url").payload       # => :catch_all
  #
  # route_set.find("/get/posts/123").found? # => true
  # route_set.find("/get/posts/one").found? # => false
  # ```
  class RouteSet(T)
    @trunk : RouteSet(T)?
    @route : T?
    @min_priority : Int32

    # Split segment storage by type for faster lookups.
    # Fixed segments use a Hash for O(1) lookup (the common case).
    # Variable segments are stored in a small Array (usually 0-2 per node).
    # At most one glob segment per node.
    # Terminal segments stored separately.
    @fixed_segments = Hash(String, FixedSegment(T)).new
    @fixed_span_segments = Hash(SegmentView, FixedSegment(T)).new
    @variable_segments = Array(VariableSegment(T)).new(initial_capacity: 2)
    @glob_segment : GlobSegment(T)? = nil
    @terminal_segments = Array(TerminalSegment(T)).new

    def initialize(@root = true)
      @insert_count = 0
      @min_priority = Int32::MAX
    end

    def min_priority : Int32
      @min_priority
    end

    # Look for or create a subtree matching a given segment.
    private def find_subtree!(segment : String, constraints : Hash(String, Regex)) : Segment(T)
      if subtree = find_subtree segment
        subtree
      else
        case segment
        when .starts_with? ':'
          new_segment = VariableSegment(T).new(segment, constraints[segment.lchop(':')]?)
          @variable_segments.push new_segment
        when .starts_with? '*'
          new_segment = GlobSegment(T).new(segment)
          @glob_segment = new_segment
        else
          new_segment = FixedSegment(T).new(segment)
          @fixed_segments[segment] = new_segment
          @fixed_span_segments[SegmentView.new(segment)] = new_segment
        end

        new_segment
      end
    end

    # Look for and return a subtree matching a given segment.
    private def find_subtree(url_segment : String) : Segment(T)?
      # Check fixed segments first (O(1) hash lookup)
      if fixed = @fixed_segments[url_segment]?
        return fixed
      end

      # Check variable segments (O(n) but n is typically 0-2)
      @variable_segments.each do |segment|
        return segment if segment.literal_match? url_segment
      end

      # Check glob segment
      if glob = @glob_segment
        return glob if glob.literal_match? url_segment
      end

      nil
    end

    def routes? : Bool
      @fixed_segments.any? || @variable_segments.any? || !@glob_segment.nil? || @terminal_segments.any?
    end

    # Recursively search the routing tree for potential matches to a given path.
    protected def select_routes(path : Array(String), path_offset = 0) : Array(RoutedResult(T))
      accepting_terminal_segments = path_offset == path.size
      can_recurse = path_offset <= path.size - 1

      matches = [] of RoutedResult(T)

      # Check terminal segments
      if accepting_terminal_segments
        @terminal_segments.each do |terminal|
          matches << RoutedResult(T).new terminal
        end
      end

      if can_recurse
        current_segment = path[path_offset]

        # Check fixed segments (O(1) hash lookup)
        if fixed = @fixed_segments[current_segment]?
          matched_routes = fixed.route_set.select_routes(path, path_offset + 1)
          matched_routes.each do |matched_route|
            matches << matched_route
          end
        end

        # Check variable segments
        @variable_segments.each do |segment|
          next unless segment.match? current_segment

          matched_routes = segment.route_set.select_routes(path, path_offset + 1)
          matched_routes.each do |matched_route|
            matched_route[segment.parameter] = URI.decode current_segment
            matches << matched_route
          end
        end

        # Check glob segment
        if glob = @glob_segment
          glob_matches = glob.route_set.reverse_select_routes(path)

          glob_matches.each do |glob_match|
            if glob.parametric?
              glob_match.routed_result[glob.parameter] = URI.decode path[path_offset..glob_match.match_position].join('/')
            end

            matches << glob_match.routed_result
          end
        end
      end

      matches
    end

    # Recursively matches the right hand side of a glob segment.
    # Allows for routes like `/a/b/*/d/e` and `/a/b/*/f/g` to coexist.
    protected def reverse_select_routes(path : Array(String)) : Array(GlobMatch(T))
      matches = [] of GlobMatch(T)

      # Check terminal segments
      @terminal_segments.each do |terminal|
        match = GlobMatch(T).new terminal, path
        matches << match
      end

      # Check fixed segments
      @fixed_segments.each_value do |segment|
        glob_matches = segment.route_set.reverse_select_routes path

        glob_matches.each do |glob_match|
          if segment.match? glob_match.current_segment
            glob_match.match_position -= 1
            matches << glob_match
          end
        end
      end

      # Check variable segments
      @variable_segments.each do |segment|
        glob_matches = segment.route_set.reverse_select_routes path

        glob_matches.each do |glob_match|
          if segment.match? glob_match.current_segment
            if segment.parametric?
              # Defer decoding path paramter to `#select_routes` to avoid double decoding.
              glob_match.routed_result[segment.parameter] = glob_match.current_segment
            end

            glob_match.match_position -= 1
            matches << glob_match
          end
        end
      end

      matches
    end

    # Find a route which is compatible with a path.
    def find(path : String) : RoutedResult(T)
      segments = split_path path
      matches = select_routes(segments)

      case matches.size
      when 0
        RoutedResult(T).new nil
      when 1
        matches.first
      else
        matches.sort.first
      end
    end

    # Finds only the insertion-order winner and prunes subtrees that cannot
    # improve it. Kept separate from #find while the strategy is benchmarked.
    def find_best(path : String) : RoutedResult(T)
      select_best_route(split_path(path)) || RoutedResult(T).new(nil)
    end

    # Selects a fixed root branch without concatenating it onto the request
    # path. HTTP routers use this to avoid constructing "get/path" per request.
    def find_best(root_segment : String, path : String) : RoutedResult(T)
      if fixed = @fixed_segments[root_segment]?
        fixed.route_set.select_best_route(split_path(path)) || RoutedResult(T).new(nil)
      else
        RoutedResult(T).new(nil)
      end
    end

    # Matches directly against byte spans in the source path. This avoids the
    # Array(String) and substring allocations made by #split_path.
    def find_span(path : String) : RoutedResult(T)
      select_best_span(path) || RoutedResult(T).new(nil)
    end

    # Selects an already-normalized fixed root before scanning the path.
    def find_span(root_segment : String, path : String) : RoutedResult(T)
      if fixed = @fixed_segments[root_segment]?
        fixed.route_set.select_best_span(path) || RoutedResult(T).new(nil)
      else
        RoutedResult(T).new(nil)
      end
    end

    # Returns the routes which are compatible with the provided *path*.
    def find_routes(path : String) : Array(RoutedResult(T))
      select_routes split_path path
    end

    protected def select_best_route(path : Array(String), path_offset = 0) : RoutedResult(T)?
      best : RoutedResult(T)? = nil

      if path_offset == path.size
        @terminal_segments.each do |terminal|
          best = pick_better_route(best, RoutedResult(T).new(terminal))
        end
      end

      if path_offset < path.size
        current_segment = path[path_offset]

        if fixed = @fixed_segments[current_segment]?
          if branch_can_beat?(best, fixed.route_set.min_priority)
            if candidate = fixed.route_set.select_best_route(path, path_offset + 1)
              best = pick_better_route(best, candidate)
            end
          end
        end

        @variable_segments.each do |segment|
          next unless segment.match?(current_segment)
          next unless branch_can_beat?(best, segment.route_set.min_priority)

          if candidate = segment.route_set.select_best_route(path, path_offset + 1)
            candidate[segment.parameter] = decode_if_escaped(current_segment)
            best = pick_better_route(best, candidate)
          end
        end

        if glob = @glob_segment
          if branch_can_beat?(best, glob.route_set.min_priority)
            if glob_match = glob.route_set.reverse_select_best_route(path)
              if glob.parametric?
                glob_match.routed_result[glob.parameter] = decode_joined_path(path, path_offset, glob_match.match_position)
              end
              best = pick_better_route(best, glob_match.routed_result)
            end
          end
        end
      end

      best
    end

    protected def reverse_select_best_route(path : Array(String)) : GlobMatch(T)?
      best : GlobMatch(T)? = nil

      @terminal_segments.each do |terminal|
        best = pick_better_glob_match(best, GlobMatch(T).new(terminal, path))
      end

      @fixed_segments.each_value do |segment|
        next unless branch_can_beat_glob?(best, segment.route_set.min_priority)

        if glob_match = segment.route_set.reverse_select_best_route(path)
          if segment.match?(glob_match.current_segment)
            glob_match.match_position -= 1
            best = pick_better_glob_match(best, glob_match)
          end
        end
      end

      @variable_segments.each do |segment|
        next unless branch_can_beat_glob?(best, segment.route_set.min_priority)

        if glob_match = segment.route_set.reverse_select_best_route(path)
          if segment.match?(glob_match.current_segment)
            if segment.parametric?
              glob_match.routed_result[segment.parameter] = glob_match.current_segment
            end
            glob_match.match_position -= 1
            best = pick_better_glob_match(best, glob_match)
          end
        end
      end

      best
    end

    protected def select_best_span(path : String, path_offset = 0) : RoutedResult(T)?
      current = next_segment(path, path_offset)
      best : RoutedResult(T)? = nil

      unless current
        @terminal_segments.each do |terminal|
          best = pick_better_route(best, RoutedResult(T).new(terminal))
        end
        return best
      end

      current_segment, next_offset = current

      if fixed = @fixed_span_segments[current_segment]?
        if branch_can_beat?(best, fixed.route_set.min_priority)
          if candidate = fixed.route_set.select_best_span(path, next_offset)
            best = pick_better_route(best, candidate)
          end
        end
      end

      @variable_segments.each do |segment|
        next unless segment.match_span?(path, current_segment.byte_offset, current_segment.bytesize)
        next unless branch_can_beat?(best, segment.route_set.min_priority)

        if candidate = segment.route_set.select_best_span(path, next_offset)
          candidate.capture(segment.parameter, path, current_segment.byte_offset, current_segment.bytesize)
          best = pick_better_route(best, candidate)
        end
      end

      if glob = @glob_segment
        if branch_can_beat?(best, glob.route_set.min_priority)
          if glob_match = glob.route_set.reverse_select_best_span(path, path.bytesize)
            glob_end = trim_separators(path, glob_match.match_end, current_segment.byte_offset)

            if glob_end > current_segment.byte_offset
              if glob.parametric?
                glob_match.routed_result.capture(
                  glob.parameter,
                  path,
                  current_segment.byte_offset,
                  glob_end - current_segment.byte_offset,
                  collapse_slashes: true
                )
              end
              best = pick_better_route(best, glob_match.routed_result)
            end
          end
        end
      end

      best
    end

    protected def reverse_select_best_span(path : String, path_end : Int32) : SpanGlobMatch(T)?
      best : SpanGlobMatch(T)? = nil

      @terminal_segments.each do |terminal|
        candidate = SpanGlobMatch(T).new(RoutedResult(T).new(terminal), path_end)
        best = pick_better_span_glob(best, candidate)
      end

      @fixed_segments.each_value do |segment|
        next unless branch_can_beat_span_glob?(best, segment.route_set.min_priority)

        if candidate = segment.route_set.reverse_select_best_span(path, path_end)
          if current_segment = previous_segment(path, candidate.match_end)
            if current_segment == SegmentView.new(segment.segment)
              matched = SpanGlobMatch(T).new(candidate.routed_result, current_segment.byte_offset)
              best = pick_better_span_glob(best, matched)
            end
          end
        end
      end

      @variable_segments.each do |segment|
        next unless branch_can_beat_span_glob?(best, segment.route_set.min_priority)

        if candidate = segment.route_set.reverse_select_best_span(path, path_end)
          if current_segment = previous_segment(path, candidate.match_end)
            if segment.match_span?(path, current_segment.byte_offset, current_segment.bytesize)
              candidate.routed_result.capture(
                segment.parameter,
                path,
                current_segment.byte_offset,
                current_segment.bytesize
              )
              matched = SpanGlobMatch(T).new(candidate.routed_result, current_segment.byte_offset)
              best = pick_better_span_glob(best, matched)
            end
          end
        end
      end

      best
    end

    # Produces a readable, indented rendering of the tree.
    def formatted_s(*, ts = 0)
      result = ""

      @terminal_segments.each do |terminal|
        result += terminal.formatted_s(ts: ts + 1)
      end

      @fixed_segments.each_value do |segment|
        result += segment.formatted_s(ts: ts + 1)
      end

      @variable_segments.each do |segment|
        result += segment.formatted_s(ts: ts + 1)
      end

      if glob = @glob_segment
        result += glob.formatted_s(ts: ts + 1)
      end

      result
    end

    private def parse_subpaths(path : String) : Array(String)
      Parsers::OptionalSegmentResolver.resolve path
    end

    private def pick_better_route(current : RoutedResult(T)?, candidate : RoutedResult(T)) : RoutedResult(T)
      return candidate unless current
      candidate.priority < current.priority ? candidate : current
    end

    private def pick_better_glob_match(current : GlobMatch(T)?, candidate : GlobMatch(T)) : GlobMatch(T)
      return candidate unless current
      candidate.routed_result.priority < current.routed_result.priority ? candidate : current
    end

    private def pick_better_span_glob(current : SpanGlobMatch(T)?, candidate : SpanGlobMatch(T)) : SpanGlobMatch(T)
      return candidate unless current
      candidate.routed_result.priority < current.routed_result.priority ? candidate : current
    end

    private def branch_can_beat?(current : RoutedResult(T)?, branch_min_priority : Int32) : Bool
      current.nil? || branch_min_priority < current.priority
    end

    private def branch_can_beat_glob?(current : GlobMatch(T)?, branch_min_priority : Int32) : Bool
      current.nil? || branch_min_priority < current.routed_result.priority
    end

    private def branch_can_beat_span_glob?(current : SpanGlobMatch(T)?, branch_min_priority : Int32) : Bool
      current.nil? || branch_min_priority < current.routed_result.priority
    end

    private def next_segment(path : String, path_offset : Int32) : {SegmentView, Int32}?
      offset = path_offset
      path_size = path.bytesize
      while offset < path_size && path.byte_at(offset) == '/'.ord
        offset += 1
      end
      return nil if offset >= path_size

      segment_start = offset
      while offset < path_size && path.byte_at(offset) != '/'.ord
        offset += 1
      end
      {SegmentView.new(path, segment_start, offset - segment_start), offset}
    end

    private def previous_segment(path : String, path_end : Int32) : SegmentView?
      offset = path_end
      while offset > 0 && path.byte_at(offset - 1) == '/'.ord
        offset -= 1
      end
      return nil if offset <= 0

      segment_end = offset
      while offset > 0 && path.byte_at(offset - 1) != '/'.ord
        offset -= 1
      end
      SegmentView.new(path, offset, segment_end - offset)
    end

    private def trim_separators(path : String, path_end : Int32, lower_bound : Int32) : Int32
      offset = path_end
      while offset > lower_bound && path.byte_at(offset - 1) == '/'.ord
        offset -= 1
      end
      offset
    end

    private def add_route(path, payload : T, constraints : Hash(String, Regex)) : Nil
      if path.includes?('(') || path.includes?(')')
        paths = parse_subpaths path
      else
        paths = [path]
      end

      paths.each do |p|
        segments = split_path p
        add(segments, payload, p, constraints, @insert_count)
        @insert_count += 1
      end
    end

    # Add a route to the tree.
    def add(path, payload : T, constraints : Hash(String, Regex) = {} of String => Regex) : Nil
      add_route path, payload, constraints
    end

    # ditto
    def add(path, payload : T, constraints : Hash(Symbol, Regex) | NamedTuple) : Nil
      add_route path, payload, constraints.to_h.transform_keys(&.to_s)
    end

    private def decode_if_escaped(value : String) : String
      value.includes?('%') ? URI.decode(value) : value
    end

    private def decode_joined_path(path : Array(String), start_index : Int32, end_index : Int32) : String
      decode_if_escaped(path[start_index..end_index].join('/'))
    end

    # Recursively find or create subtrees matching a given path, and store the
    # application route at the leaf. Uses an index to avoid O(n) Array#shift.
    protected def add(url_segments : Array(String), route : T, full_path : String, constraints : Hash(String, Regex), priority : Int32 = 0, index : Int32 = 0) : Nil
      @min_priority = priority if priority < @min_priority

      if index >= url_segments.size
        segment = TerminalSegment(T).new(route, full_path, priority)
        @terminal_segments.push segment
        return
      end

      segment = find_subtree! url_segments[index], constraints
      segment.route_set.add(url_segments, route, full_path, constraints, priority, index + 1)
    end

    # Split a path by slashes, remove blanks, and compact the path array.
    # Uses block form of split and pre-allocates to avoid intermediate array.
    #
    # ```
    # split_path("/a/b/c/d") # => ["a", "b", "c", "d"]
    # ```
    private def split_path(path : String) : Array(String)
      segments = Array(String).new(path.count('/'))
      path.split('/') do |segment|
        segments << segment unless segment.empty?
      end
      segments
    end
  end
end

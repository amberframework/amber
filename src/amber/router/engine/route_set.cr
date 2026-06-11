require "uri"

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

    # Split segment storage by type for faster lookups.
    # Fixed segments use a Hash for O(1) lookup (the common case).
    # Variable segments are stored in a small Array (usually 0-2 per node).
    # At most one glob segment per node.
    # Terminal segments stored separately.
    @fixed_segments = Hash(String, FixedSegment(T)).new
    @variable_segments = Array(VariableSegment(T)).new(initial_capacity: 2)
    @glob_segment : GlobSegment(T)? = nil
    @terminal_segments = Array(TerminalSegment(T)).new

    def initialize(@root = true)
      @insert_count = 0
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

    # Returns the routes which are compatible with the provided *path*.
    def find_routes(path : String) : Array(RoutedResult(T))
      select_routes split_path path
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

    # Recursively find or create subtrees matching a given path, and store the
    # application route at the leaf. Uses an index to avoid O(n) Array#shift.
    protected def add(url_segments : Array(String), route : T, full_path : String, constraints : Hash(String, Regex), priority : Int32 = 0, index : Int32 = 0) : Nil
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

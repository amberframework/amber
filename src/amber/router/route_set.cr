module Amber
  module Router
    class RouteSet
      @trunk : RouteSet?
      @route : Route?

      property segment : String
      property segment_type = 0
      property full_path : String?

      ROOT = 1
      FIXED = 2
      VARIABLE = 4
      GLOB = 8

      # A tree data structure (recursive). The initial construction has an segment
      # of "root" and no trunk. Subtrees must pass in these details upon creation.
      def initialize(@segment = "#", @trunk = nil)
        @branches = Array(RouteSet).new

        if @trunk
          @segment_type = FIXED

          if @segment.starts_with? ':'
            @segment_type = VARIABLE
          end

          if @segment.starts_with? '*'
            @segment_type = GLOB
          end

        else
          @segment_type = ROOT
        end
      end

      def deep_clone : RouteSet
        clone = {{@type}}.allocate
        clone.initialize_copy(self)
        clone
      end

      protected def initialize_copy(other) : Nil
        @route = other.@route
        @trunk = nil
        @segment = other.@segment

        @segment_type = other.@segment_type
        @full_path = other.@full_path

        @branches = other.@branches.map { |s| s.deep_clone.as(RouteSet) }
      end

      # Look for or create a subtree matching a given segment.
      def find_subtree!(segment : String) : RouteSet
        if subtree = find_subtree segment
          subtree
        else
          RouteSet.new(segment, self).tap do |subtree|
            @branches.push subtree
          end
        end
      end

      # Look for and return a subtree matching a given segment.
      def find_subtree(segment : String) : RouteSet?
        @branches.each do |subtree|
          break subtree if subtree.segment_match? segment
        end
      end

      def segment_match?(segment : String) : Bool
        segment == @segment
      end

      def root? : Bool
        @segment_type == ROOT
      end

      def fixed? : Bool
        @segment_type == FIXED
      end

      def variable? : Bool
        @segment_type == VARIABLE
      end

      def glob? : Bool
        @segment_type == GLOB
      end

      def leaf? : Bool
        @branches.size == 0
      end

      def routes? : Bool
        @branches.any?
      end

      # Recursively count the number of discrete paths remaining in the tree.
      def size
        return 1 if leaf?

        @branches.reduce 0 do |count, branch|
          count += branch.size
        end
      end

      # Recursively descend to find the attached application route.
      # Weakness: assumes only one path remains in the tree.
      def route
        return @route if leaf?
        @branches.first.route
      end

      # Recursively _prunes_ the route tree by matching segments
      # against path segment strings.
      #
      # A destructive breadth first search.
      #
      # return true if any routes matched.
      def select_routes!(path : String) : Bool
        first_segment, remaining_path = split_path path

        reverse_match = false

        case
        when root?
          # select all branches that match the full path
          remaining_path = path
        when fixed?
          # select branches only if this segment matches
          segment_match? first_segment
        when variable?
          # always match
        when glob?
          reverse_match = true
        end

        if reverse_match
          match, _ = reverse_select_routes! path
          return match
        else
          @branches.select! do |subtree|
            subtree.select_routes! remaining_path
          end
        end

        @branches.any? || (leaf? && remaining_path == "")
      end

      # Recursively matches the right hand side of a glob segment.
      # Allows for routes like /a/b/*/d/e and /a/b/*/f/g to coexist.
      # This is a modified version of a destructive depth first search.
      #
      # Importantly, each subtree must pass back up the remaining part
      # of the path so it can be matched against the parent, so this
      # method somewhat awkwardly returns:
      #
      #   Tuple(subtree_match : Bool, path_for_trunk_to_match : String)
      #
      def reverse_select_routes!(path : String) : Tuple(Bool, String)
        remnant_path = ""
        was_leaf = leaf?

        @branches.select! do |subtree|
          match, remaining_path = subtree.reverse_select_routes! path
          if match

            if remnant_path != ""
              raise "warning: overwriting remnant path"
            end

            remnant_path = remaining_path
          end
        end

        # If this segment started as a leaf, no remant path exists. Match against the whole path.
        remnant_path = path if was_leaf

        # If this wasn't a leaf and there are no branches left, it's not a match.
        return Tuple(Bool, String).new(false, "") unless @branches.any? || was_leaf

        # If this node is the glob, at least one subtree matched (or there are none).
        return Tuple(Bool, String).new(true, "") if glob?

        remaining_path, last_segment = reverse_split_path remnant_path

        matched = case
        when fixed?
          segment_match? last_segment
        when variable?
          true
        else
          false
        end

        Tuple(Bool, String).new(matched, remaining_path)
      end

      # Add a route to the tree.
      def add(path, route : Route) : Nil
        add(path, route, path)
      end

      # Recursively find or create subtrees matching a given path, and store the
      # application route at the leaf.
      protected def add(path : String, route : Route, full_path : String) : Nil
        if path == ""
          if @route.nil?
            @route = route
            @full_path = full_path
            return
          else
            raise "Unable to store route: #{full_path}, route is already defined as #{@full_path}"
          end
        end

        first_segment, remaining_path = split_path path

        subtree = find_subtree! first_segment
        subtree.add(remaining_path, route, full_path)
      end

      # Find a route which has been assigned to a matching path
      # Weakness: assumes only one route will match the path query.
      def find(path) : Amber::Route?
        matches = deep_clone
        matches.select_routes!(path)

        if matches.size > 1
          raise "Warning: matched multiple routes"
        end

        matches.route
      end

      # Produces a readable indented rendering of the tree, though
      # not really compatible with the other components of a deep object inspection
      def inspect(*, ts = 0)
        tab = "  " * ts
        @branches.reduce("#{@segment} :\n") do |s, subtree|
          if subtree.routes?
            s += "#{tab}- #{subtree.inspect(ts: ts + 1)}"
          else
            s += "#{tab}- #{subtree.segment} (#{subtree.full_path})\n"
          end

          s
        end
      end

      # Split a path by slashes, and return the first segment and the rest untouched.
      #
      # E.g. split_path("/a/b/c/d") => "a", "b/c/d"
      private def split_path(path : String) : Tuple(String, String)
        first_segment = path.split("/").first

        if path.size >= first_segment.size + 1
          remaining_path = path[first_segment.size + 1..-1]
        else
          remaining_path = ""
        end

        Tuple(String, String).new(first_segment, remaining_path)
      end

      # Split a path by slashes, and return the last segment and the rest untouched.
      #
      # E.g. split_path("/a/b/c/d") => "a/b/c", "d"
      private def reverse_split_path(path : String) : Tuple(String, String)
        last_segment = path.split("/").last

        if path.size >= last_segment.size + 1
          remaining_path = path[0...last_segment.size * -1 - 1]
        else
          remaining_path = ""
        end

        Tuple(String, String).new(remaining_path, last_segment)
      end

    end
  end
end

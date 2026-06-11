module Amber::Router::Parsers
  # Resolves "optional" segments in urls to many urls.
  #
  # In this class an optional is a parenthetical statement. For example, these
  # urls all have one or more optional segments:
  #
  # - `users/:id(.format)`
  # - `relatives(/:id/children)`
  # - `students(/peers(/teachers))`
  #
  # This resolver pays no attention to url structure _other_ than parenthesis.
  # As a result, care should be taken to properly structure optionals so that
  # resolved urls are valid. It is easiest to maintain valid resolved urls by
  # consistently placing delimiters relative to optional boundaries.
  # For example:
  #
  # All optionals _begin_ with a delimiter: `users/:id(/children(/grandchildren))/`
  # All optionals _end_ with a delimiter: `users/:id/(children/(grandchildren/))`
  #
  # Both examples produce the same result, which is this set of paths:
  #
  #     [
  #       "users/:id/",
  #       "users/:id/children/",
  #       "users/:id/children/grandchildren/",
  #     ]
  #
  # However, it is unwise to mix styles because it results in incorrect
  # url delimiters.
  #
  # For example: `users/:id(/children/(grandchildren/))/cousins`
  #
  # Produces this set of paths:
  #
  #   [
  #     "users/:id/cousins",
  #     "users/:id/children//cousins",
  #     "users/:id/children/grandchildren//cousins",
  #   ]
  #
  class OptionalSegmentResolver
    def self.necessary?(path : String) : Bool
      path.includes?('(') || path.includes?(')')
    end

    # Converts a path url with parenthesis into a walkable array
    # of segments.
    #
    # ` users/:id(/children(/:gender))/grade/(:letter)`
    #
    #  [
    #    "users/:id",  "(",  "/children",  "(",  "/:gender",  ")",  ")",
    #    "/grade/",  "(",  ":letter",  ")"
    #  ]
    protected def segmentize(path : String) : Array(String)
      current_segment = [] of String
      segments = [] of String

      path.split("").each do |c|
        if c == "(" || c == ")"
          segments << current_segment.join unless current_segment.empty?
          segments << c
          current_segment.clear
        else
          current_segment << c
        end
      end

      segments << current_segment.join if current_segment.any?
      segments
    end

    getter paths : Array(Array(String))

    def initialize(path : String)
      @paths = [segmentize path]
    end

    def self.resolve(path : String) : Array(String)
      instance = new path
      instance.resolve
      instance.paths.map &.join
    end

    # Iterates the path array until there are no more optionals to resolve,
    # populating the `paths` array with resolutions.
    def resolve
      loop do
        index_of_path_with_optional = paths.index do |path|
          path.includes? "("
        end
        break unless index_of_path_with_optional

        new_paths = resolve_optional paths[index_of_path_with_optional]

        paths[index_of_path_with_optional] = new_paths.shift

        while new_paths.any?
          paths.insert index_of_path_with_optional, new_paths.shift
        end
      end
    end

    # Converts a single path with at least one optional into
    # two paths. One with the optional and one without.
    #
    # When a path has nested optionals, only the outermost optional is resolved.
    def resolve_optional(path : Array(String)) : Array(Array(String))
      optional_start = path.index "("

      return [path] if optional_start.nil?

      open_optionals = 0
      optional_end = nil

      position = optional_start + 1

      while position < path.size
        segment = path[position]

        case segment
        when "("
          open_optionals += 1
        when ")"
          if open_optionals > 0
            open_optionals -= 1
          else
            optional_end = position
            break
          end
        else
          # skip
        end

        position += 1
      end

      unless optional_end
        carat_position = path[0..optional_start].sum(&.size)

        indent = "  "

        message = String.build do |error|
          error << '\n'
          error << "Could not find matching closing parenthesis:\n"
          error << indent
          error << path.join
          error << '\n'
          error << indent
          error << "~" * (carat_position - 1)
          error << '^'
          error << '\n'
        end

        raise message
      end

      route_with_optional = path[0...optional_start]
      route_with_optional += path[(optional_start + 1)...optional_end]
      route_with_optional += path[(optional_end + 1)..-1]

      route_without_optional = [] of String
      route_without_optional += path[0...optional_start]
      route_without_optional += path[(optional_end + 1)..-1]

      [route_with_optional, route_without_optional]
    end
  end
end

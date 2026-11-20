require "mica/regex"
require "../../../src/amber/router/engine"

module RouterVsMica
  # Route parameter rules written on the regex engines, each a
  # `Amber::Router::ParamConstraint` so the same `RouteSet` code runs them.
  #
  # Two shapes per engine:
  #
  # * span: reads the segment in place inside the request path (no
  #   substring), the shape the hand-written rules use;
  # * slice: copies the segment out with `String#byte_slice` and matches an
  #   `\A...\z` pattern against the copy, the shape a regex-based router
  #   would take through `ParamConstraint#matches?`.
  module RuleBackend
    # The search limits every Mica rule runs under: the request-input
    # budget, the same one Mica applies to anything a request carries.
    LIMITS = Mica::Regex::SearchLimits::REQUEST

    # Mica runtime pattern, span shape: an anchored search from the
    # segment's first byte that must end exactly at the segment's end.
    struct MicaRuntimeSpan
      include Amber::Router::ParamConstraint

      getter label : String
      @expression : Mica::Regex::Expression

      def initialize(@label : String, source : String)
        @expression = Mica::Regex.compile(source, dialect: :crystal,
          compile_limits: Mica::Regex::CompileLimits::TRUSTED_PATTERN)
      end

      def matches?(segment : String) : Bool
        matches_span?(segment, 0, segment.bytesize)
      end

      def matches_span?(path : String, byte_offset : Int32, bytesize : Int32) : Bool
        span = @expression.search_span(path, byte_offset, Mica::Regex::MatchOptions::Anchored, limits: LIMITS)
        return false unless span
        span.byte_end == byte_offset + bytesize
      rescue Mica::EncodingError
        # The hand-written rules reject a segment that is not ASCII; a path
        # that is not valid UTF-8 fails the rule the same way.
        false
      end

      def to_s(io : IO) : Nil
        io << "mica_runtime_span(" << @label << ')'
      end
    end

    # Mica runtime pattern, slice shape (`\A...\z` on a copied segment).
    struct MicaRuntimeSlice
      include Amber::Router::ParamConstraint

      getter label : String
      @expression : Mica::Regex::Expression

      def initialize(@label : String, source : String)
        @expression = Mica::Regex.compile(source, dialect: :crystal,
          compile_limits: Mica::Regex::CompileLimits::TRUSTED_PATTERN)
      end

      def matches?(segment : String) : Bool
        @expression.matches_at_byte_index?(segment, 0, limits: LIMITS)
      rescue Mica::EncodingError
        false
      end

      def to_s(io : IO) : Nil
        io << "mica_runtime_slice(" << @label << ')'
      end
    end

    # Mica static pattern, span shape. A static pattern takes no match
    # options, so the search may run past the segment when the segment
    # fails; the bounds check below rejects any match that does not cover
    # the segment exactly.
    struct MicaStaticSpan(P)
      include Amber::Router::ParamConstraint

      getter label : String

      def initialize(@label : String, @pattern : P)
      end

      def matches?(segment : String) : Bool
        matches_span?(segment, 0, segment.bytesize)
      end

      def matches_span?(path : String, byte_offset : Int32, bytesize : Int32) : Bool
        span = @pattern.search_span(path, byte_offset, limits: LIMITS)
        return false unless span
        span.byte_begin == byte_offset && span.byte_end == byte_offset + bytesize
      rescue Mica::EncodingError
        false
      end

      def to_s(io : IO) : Nil
        io << "mica_static_span(" << @label << ')'
      end
    end

    # Diagnostic only: `MicaStaticSpan` through the `:nodoc:` unchecked entry
    # point, which skips the per-call UTF-8 validation of the whole path. It
    # shows how much of the static span cost is that validation; a router
    # would have to validate the path once itself before using it; the
    # agreement gate feeds it valid UTF-8 only.
    struct MicaStaticSpanUnchecked(P)
      include Amber::Router::ParamConstraint

      getter label : String

      def initialize(@label : String, @pattern : P)
      end

      def matches?(segment : String) : Bool
        matches_span?(segment, 0, segment.bytesize)
      end

      def matches_span?(path : String, byte_offset : Int32, bytesize : Int32) : Bool
        span = @pattern.search_span_unchecked(path, byte_offset, LIMITS, nil)
        return false unless span
        span.byte_begin == byte_offset && span.byte_end == byte_offset + bytesize
      end

      def to_s(io : IO) : Nil
        io << "mica_static_span_unchecked(" << @label << ')'
      end
    end

    # Mica static pattern, slice shape (`\A...\z` on a copied segment).
    struct MicaStaticSlice(P)
      include Amber::Router::ParamConstraint

      getter label : String

      def initialize(@label : String, @pattern : P)
      end

      def matches?(segment : String) : Bool
        @pattern.matches?(segment, limits: LIMITS)
      rescue Mica::EncodingError
        false
      end

      def to_s(io : IO) : Nil
        io << "mica_static_slice(" << @label << ')'
      end
    end

    # Stdlib Regex (PCRE2 with JIT), span shape: an anchored match at the
    # segment's first byte followed by `(?![^/])`, so the match must end
    # where the segment ends.
    struct StdlibSpan
      include Amber::Router::ParamConstraint

      getter label : String
      @regex : Regex

      def initialize(@label : String, source : String)
        @regex = Regex.new("(?:#{source})(?![^/])")
      end

      def matches?(segment : String) : Bool
        matches_span?(segment, 0, segment.bytesize)
      end

      def matches_span?(path : String, byte_offset : Int32, bytesize : Int32) : Bool
        @regex.matches_at_byte_index?(path, byte_offset, Regex::MatchOptions::ANCHORED)
      end

      def to_s(io : IO) : Nil
        io << "stdlib_span(" << @label << ')'
      end
    end

    # Stdlib Regex, slice shape (`\A...\z` on a copied segment).
    struct StdlibSlice
      include Amber::Router::ParamConstraint

      getter label : String
      @regex : Regex

      def initialize(@label : String, source : String)
        @regex = Regex.new("\\A(?:#{source})\\z")
      end

      def matches?(segment : String) : Bool
        @regex.matches?(segment)
      end

      def to_s(io : IO) : Nil
        io << "stdlib_slice(" << @label << ')'
      end
    end
  end
end

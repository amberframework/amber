require "./param_constraint"
require "./param_constraints/*"

module Amber::Router
  # The built-in route parameter rules, and the conversion from what a route
  # definition writes to the rules the router stores.
  #
  # A route names a rule by symbol or passes a rule value:
  #
  # ```
  # get "/posts/:id", PostsController, :show, {"id" => :numeric}
  # get "/objects/:key", ObjectsController, :show, {key: Amber::Router::ParamConstraints::UUID}
  # get "/codes/:code", CodesController, :show, {"code" => Amber::Router::ParamConstraints::NUMERIC.with_length(3)}
  # ```
  module ParamConstraints
    # One or more ASCII digits.
    NUMERIC = CharacterRun.new("numeric", '0'..'9')
    # One or more ASCII letters.
    ALPHA = CharacterRun.new("alpha", 'a'..'z', 'A'..'Z')
    # One or more ASCII letters and digits.
    ALNUM = CharacterRun.new("alnum", 'a'..'z', 'A'..'Z', '0'..'9')
    # One or more hexadecimal digits, in either letter case.
    HEX = CharacterRun.new("hex", '0'..'9', 'a'..'f', 'A'..'F')
    # A lowercase slug; see `Slug`.
    SLUG = Slug.new
    # A hyphenated UUID; see `Uuid`.
    UUID = Uuid.new

    # The rules a route can name by symbol.
    PRESETS = {
      :numeric => NUMERIC,
      :uuid    => UUID,
      :slug    => SLUG,
      :alpha   => ALPHA,
      :alnum   => ALNUM,
      :hex     => HEX,
    } of Symbol => ParamConstraint

    # Raised when a route names a rule symbol that `PRESETS` does not hold.
    class UnknownPresetError < ArgumentError
      def initialize(preset : Symbol)
        super("Unknown route parameter constraint :#{preset}. Known presets: #{PRESETS.keys.map { |key| ":#{key}" }.join(", ")}")
      end
    end

    # Returns *constraints* keyed by parameter name, with every symbol
    # replaced by its preset rule. Raises `UnknownPresetError` for a symbol
    # that is not a preset.
    def self.normalize(constraints : Hash | NamedTuple) : Hash(String, ParamConstraint)
      normalized = {} of String => ParamConstraint
      constraints.each do |parameter, rule|
        normalized[parameter.to_s] = resolve(rule)
      end
      normalized
    end

    # :nodoc:
    def self.resolve(rule : ParamConstraint) : ParamConstraint
      rule
    end

    # :nodoc:
    def self.resolve(rule : Symbol) : ParamConstraint
      PRESETS[rule]? || raise UnknownPresetError.new(rule)
    end
  end
end
